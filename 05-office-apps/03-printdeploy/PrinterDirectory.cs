using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace InstaladorImpresoras
{
    sealed class OfficePrinter
    {
        public string Office, Location, Brand, Ip;
        public string Label => string.Join(" · ", new[] { Location, Brand }.Where(s => s.Length > 0).DefaultIfEmpty("Impresora"));
    }

    /// <summary>
    /// Directorio de impresoras por oficina. Orden de busqueda: oficinas.txt junto al .exe,
    /// %ProgramData%\PrintDeploy\oficinas.txt y, por ultimo, el embebido al compilar (si lo hay).
    /// </summary>
    static class PrinterDirectory
    {
        public static readonly string[] ExternalPaths =
        {
            Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "oficinas.txt"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PrintDeploy", "oficinas.txt"),
        };

        public static List<OfficePrinter> Load()
        {
            string text = null;
            var external = ExternalPaths.FirstOrDefault(File.Exists);
            if (external != null) text = File.ReadAllText(external, Encoding.UTF8);
            else
                using (var s = typeof(PrinterDirectory).Assembly.GetManifestResourceStream("oficinas.txt"))
                    if (s != null) using (var r = new StreamReader(s, Encoding.UTF8)) text = r.ReadToEnd();

            var list = new List<OfficePrinter>();
            if (text == null) return list;
            foreach (var raw in text.Split('\n'))
            {
                var line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                var p = line.Split('|').Select(x => x.Trim()).ToArray();
                if (p.Length < 4) continue;
                string clean(string v) => v == "-" ? "" : v;
                list.Add(new OfficePrinter { Office = p[0], Location = clean(p[1]), Brand = clean(p[2]), Ip = p[3] });
            }
            return list;
        }
    }

    /// <summary>Desplegable con el directorio. Clic en una fila = usar/copiar la IP.</summary>
    sealed class DirectoryPopup : Form
    {
        readonly Action<OfficePrinter> onPick;
        readonly Dictionary<OfficePrinter, bool?> status = new Dictionary<OfficePrinter, bool?>();
        readonly List<(Rectangle rect, OfficePrinter p)> hits = new List<(Rectangle, OfficePrinter)>();
        readonly List<OfficePrinter> items;
        OfficePrinter hover;
        readonly Font fHead = Theme.Mono(7.5f, FontStyle.Bold), fOffice = Theme.Serif(11.5f), fRow = Theme.Sans(9.5f), fIp = Theme.Mono(9.5f), fHint = Theme.Mono(7f);
        int S(int px) => (int)Math.Round(px * DeviceDpi / 96.0);

        public DirectoryPopup(List<OfficePrinter> items, Action<OfficePrinter> onPick)
        {
            this.items = items;
            this.onPick = onPick;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            BackColor = Theme.Paper;
            DoubleBuffered = true;
            KeyPreview = true;
            KeyDown += (s, e) => { if (e.KeyCode == Keys.Escape) Close(); };
            Deactivate += (s, e) => Close();
            int offices = items.Select(i => i.Office).Distinct().Count();
            Size = new Size(S(420), S(52) + offices * S(38) + items.Count * S(34) + S(48));
            foreach (var p in items) status[p] = null;
            Shown += (s, e) => CheckAll();
        }

        protected override CreateParams CreateParams
        {
            get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; return cp; } // sombra
        }

        void CheckAll()
        {
            foreach (var p in items)
            {
                var item = p;
                Task.Run(() => PrinterProbe.TcpOpen(item.Ip, 9100, 1200) || PrinterProbe.TcpOpen(item.Ip, 80, 800))
                    .ContinueWith(t => { if (!IsDisposed) BeginInvoke((Action)(() => { status[item] = t.Result; Invalidate(); })); });
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            hits.Clear();
            int pad = S(20), y = 0, w = Width;

            // cabecera
            using (var b = new SolidBrush(Theme.Black)) g.FillRectangle(b, 0, 0, w, S(40));
            using (var b = new SolidBrush(Theme.Red)) g.FillRectangle(b, pad, S(13), S(3), S(14));
            Theme.DrawGradientText(g, Theme.Caps("Directorio de impresoras"), fHead, new Point(pad + S(10), S(14)), Theme.RedOnDark, Theme.Paper);
            y = S(52);

            foreach (var office in items.GroupBy(i => i.Office))
            {
                TextRenderer.DrawText(g, office.Key, fOffice, new Rectangle(pad, y, w - 2 * pad, S(30)), Theme.Black, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                using (var p = new Pen(Theme.Black)) g.DrawLine(p, pad, y + S(32), w - pad, y + S(32));
                y += S(38);
                foreach (var it in office)
                {
                    var r = new Rectangle(0, y, w, S(34));
                    hits.Add((r, it));
                    if (it == hover) using (var b = new SolidBrush(Theme.Hover)) g.FillRectangle(b, r);
                    if (it == hover) using (var b = new SolidBrush(Theme.Red)) g.FillRectangle(b, 0, y, S(3), r.Height);

                    // estado: punto negro = responde, circulo rojo = sin respuesta, gris = comprobando
                    var dot = new Rectangle(pad + S(2), y + r.Height / 2 - S(4), S(8), S(8));
                    var st = status[it];
                    if (st == true) using (var b = new SolidBrush(Theme.Black)) g.FillEllipse(b, dot);
                    else if (st == false) using (var p = new Pen(Theme.Red, S(2))) g.DrawEllipse(p, dot);
                    else using (var p = new Pen(Theme.Line, S(2))) g.DrawEllipse(p, dot);

                    TextRenderer.DrawText(g, it.Label, fRow, new Rectangle(pad + S(20), y, w - S(210), r.Height), Theme.Black, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding);
                    TextRenderer.DrawText(g, it.Ip, fIp, new Rectangle(w - S(170), y, S(170) - pad, r.Height), st == false ? Theme.Red : Theme.Muted, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                    y += r.Height;
                }
                y += S(4);
            }
            TextRenderer.DrawText(g, "●  responde    ○  sin respuesta    ·  clic = usar IP", fHint, new Rectangle(pad, Height - S(28), w - 2 * pad, S(20)), Theme.Muted, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            using (var p = new Pen(Theme.Black)) { g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.None; g.DrawRectangle(p, 0, 0, Width - 1, Height - 1); }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            var h = hits.FirstOrDefault(x => x.rect.Contains(e.Location)).p;
            if (h != hover) { hover = h; Cursor = h != null ? Cursors.Hand : Cursors.Default; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { hover = null; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            var h = hits.FirstOrDefault(x => x.rect.Contains(e.Location)).p;
            if (h != null) { Close(); onPick(h); }
            base.OnMouseClick(e);
        }
    }
}

