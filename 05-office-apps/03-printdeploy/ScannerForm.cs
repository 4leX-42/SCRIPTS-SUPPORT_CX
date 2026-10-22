using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace InstaladorImpresoras
{
    /// <summary>
    /// Escaner de red: comprueba el directorio de oficinas y busca impresoras en un rango de IPs.
    /// Verde = online (impresora detectada), rojo = offline / no es impresora. Instalar = directo, con el modelo ya detectado.
    /// Al cerrar se oculta: los resultados se conservan mientras la app siga abierta.
    /// </summary>
    sealed class ScannerForm : Form
    {
        const string DirectoryGroup = "Directorio";
        const int Parallel = 128;

        readonly Action<ScanEntry> onInstall;
        readonly ScanList list = new ScanList { Dock = DockStyle.Fill };
        readonly BufferedPanel head = new BufferedPanel(), toolbar = new BufferedPanel(), detail = new BufferedPanel();
        readonly ThinProgress progress = new ThinProgress { Dock = DockStyle.Top, BarColor = Theme.Black, Visible = false };
        readonly LineField fRange = new LineField("Rango", mono: true);
        readonly FlatBtn btnScan = new FlatBtn("Escanear", primary: true);
        readonly FlatBtn btnDir = new FlatBtn("Directorio", primary: false);
        readonly FlatBtn btnInstall = new FlatBtn("Instalar", primary: true);
        readonly FlatBtn btnRetry = new FlatBtn("Reintentar", primary: false);
        readonly FlatBtn btnWeb = new FlatBtn("Web", primary: false);
        readonly FlatBtn btnCopy = new FlatBtn("Copiar", primary: false);
        readonly System.Windows.Forms.Timer repaint = new System.Windows.Forms.Timer { Interval = 50 };
        readonly Font fTag = Theme.Strong(8.5f), fSub = Theme.Mono(8f), fTitle = Theme.Title(11.5f), fData = Theme.Mono(8.75f),
                      fBody = Theme.Sans(9f), fKey = Theme.Strong(7.5f), fFoot = Theme.Sans(8.25f);
        CancellationTokenSource rangeCts;
        bool checkingDirectory, dirty;
        string dirStatus = "", rangeStatus = "", note = "";
        string Status => string.Join("   ·   ", new[] { rangeStatus, dirStatus, note }.Where(x => x.Length > 0));
        int S(int px) => (int)Math.Round(px * DeviceDpi / 96.0);

        public ScannerForm(List<OfficePrinter> directory, Action<ScanEntry> onInstall)
        {
            this.onInstall = onInstall;
            // SNMP, IPP y winspool son llamadas bloqueantes: hilos de sobra para que no hagan cola
            ThreadPool.GetMinThreads(out var workers, out var io);
            ThreadPool.SetMinThreads(Math.Max(workers, 64), Math.Max(io, 64));
            Text = "PrintDeploy · Escáner";
            FormBorderStyle = FormBorderStyle.None;
            AutoScaleMode = AutoScaleMode.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            BackColor = Theme.Paper;
            Font = Theme.Sans(9.5f);
            Padding = new Padding(1);
            ClientSize = new Size(S(820), S(720));
            KeyPreview = true;
            KeyDown += (s, e) => { if (e.KeyCode == Keys.Escape) Hide(); };
            FormClosing += (s, e) => { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };

            foreach (var p in directory)
                list.Items.Add(new ScanEntry { Ip = p.Ip, Group = DirectoryGroup, Directory = p });

            BuildHead();
            BuildToolbar();
            BuildDetail();
            list.SelectionChanged += e => UpdateDetail();
            list.Activated += e => { if (e.CanInstall) onInstall(e); };
            list.EmptyText = "Sin directorio (oficinas.txt). Escanee un rango para buscar impresoras.";

            Controls.Add(list);
            Controls.Add(detail);
            Controls.Add(progress);
            Controls.Add(toolbar);
            Controls.Add(head);

            // repintado agrupado: un escaneo de 254 IPs no repinta 254 veces
            repaint.Tick += (s, e) => { if (!dirty) return; dirty = false; list.Invalidate(); UpdateDetail(); };
            repaint.Start();
            UpdateDetail();

            bool first = true;
            Shown += (s, e) =>
            {
                if (!first) return;
                first = false;
                // primera apertura: directorio y red local a la vez
                CheckDirectory();
                if (fRange.Box.Text.Length > 0) ScanRange();
            };
        }

        protected override CreateParams CreateParams
        {
            get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; return cp; } // sombra
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (var p = new Pen(Theme.Black)) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }

        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, int w, int l);

        void BuildHead()
        {
            head.Dock = DockStyle.Top;
            head.Height = S(52);
            head.BackColor = Theme.Black;
            head.MouseDown += (s, e) => { if (e.Button == MouseButtons.Left) { ReleaseCapture(); SendMessage(Handle, 0xA1, 2, 0); } };
            head.Paint += (s, e) =>
            {
                var g = e.Graphics;
                int x = S(24);
                using (var b = new SolidBrush(Theme.Red)) g.FillRectangle(b, x, S(12), S(3), S(13));
                Theme.DrawGradientText(g, Theme.Caps("Escáner"), fTag, new Point(x + S(10), S(12)), Theme.RedOnDark, Theme.Paper);
                TextRenderer.DrawText(g, "ICMP · TCP 9100 / 631 / 515 · SNMP · SMB", fSub, new Point(x + S(10), S(30)), Color.FromArgb(150, 150, 152), TextFormatFlags.NoPadding);
            };
            var close = new IconBtn("✕", null, 10f, icon: false) { Size = new Size(S(46), S(34)), HoverBack = Theme.Red };
            close.Click += (s, e) => Hide();
            var panel = new IconBtn(Theme.GlyphPrinter, "Dispositivos e impresoras") { Size = new Size(S(40), S(34)) };
            panel.Click += (s, e) => Theme.OpenPrintersPanel();
            head.Controls.Add(close);
            head.Controls.Add(panel);
            head.Resize += (s, e) => { close.Location = new Point(head.Width - close.Width, 0); panel.Location = new Point(close.Left - panel.Width, 0); };
        }

        void BuildToolbar()
        {
            toolbar.Dock = DockStyle.Top;
            toolbar.Height = S(74);
            toolbar.BackColor = Theme.Paper;
            fRange.Box.Text = NetworkScan.LocalRange();
            fRange.Box.KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; if (rangeCts == null) ScanRange(); } };
            btnScan.Click += (s, e) => ScanRange();
            btnDir.Click += (s, e) => CheckDirectory();
            toolbar.Controls.Add(fRange);
            toolbar.Controls.Add(btnScan);
            toolbar.Controls.Add(btnDir);
            toolbar.Layout += (s, e) =>
            {
                int pad = S(24), y = S(14);
                fRange.SetBounds(pad, y, S(230), S(52));
                btnScan.SetBounds(fRange.Right + S(16), y + S(14), S(130), S(36));
                btnDir.SetBounds(toolbar.Width - pad - S(130), y + S(14), S(130), S(36));
            };
        }

        void BuildDetail()
        {
            detail.Dock = DockStyle.Bottom;
            detail.Height = S(176);
            detail.BackColor = Theme.Paper;
            detail.Paint += PaintDetail;
            btnInstall.Click += (s, e) => { var sel = list.Selected; if (sel != null && sel.CanInstall) onInstall(sel); };
            btnRetry.Click += async (s, e) => { var sel = list.Selected; if (sel != null) await CheckOne(sel, quick: false); };
            btnWeb.Click += (s, e) => { var sel = list.Selected; if (sel != null) try { Process.Start("http://" + sel.Ip); } catch { } };
            btnCopy.Click += (s, e) => { var sel = list.Selected; if (sel != null) try { Clipboard.SetText(sel.Ip); note = "copiado " + sel.Ip; detail.Invalidate(); } catch { } };
            var buttons = new[] { (btnInstall, 120), (btnRetry, 120), (btnWeb, 80), (btnCopy, 100) };
            foreach (var (b, _) in buttons) detail.Controls.Add(b);
            detail.Layout += (s, e) =>
            {
                int x = detail.Width - S(24);
                foreach (var (b, w) in buttons) { x -= S(w); b.SetBounds(x, S(100), S(w), S(34)); x -= S(8); }
            };
        }

        void PaintDetail(object sender, PaintEventArgs e)
        {
            var g = e.Graphics;
            int pad = S(24), w = detail.Width, tx = pad + S(20), tw = w - tx - pad;
            using (var b = new SolidBrush(Theme.Line)) g.FillRectangle(b, 0, 0, w, 1);
            var flags = TextFormatFlags.Left | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis;
            var sel = list.Selected;
            if (sel == null)
                TextRenderer.DrawText(g, "Seleccione un equipo.  Doble clic / Enter en uno online = instalar.", fBody, new Rectangle(pad, S(16), w - 2 * pad, S(20)), Theme.Muted, flags);
            else
            {
                var r = sel.Result;
                DrawDot(g, sel.State, new Rectangle(pad, S(17), S(12), S(12)));
                var title = sel.Directory != null ? $"{sel.Directory.Office} · {sel.Label}" : sel.Friendly.Length > 0 ? sel.Friendly : r?.Model ?? sel.Ip;
                TextRenderer.DrawText(g, title, fTitle, new Rectangle(tx, S(12), tw, S(24)), Theme.Black, flags);

                var data = sel.Ip + (r?.PingMs != null ? $"  ·  {r.PingMs} ms" : "") + (r != null && r.Ports.Count > 0 ? "  ·  tcp " + string.Join(" ", r.Ports) : "");
                TextRenderer.DrawText(g, data, fData, new Rectangle(tx, S(40), tw, S(16)), Theme.Muted, flags);

                // lo que el propio equipo dice de si mismo
                var id = r == null ? "" : string.Join("  ·  ", new[] { r.Name, r.Location }.Where(x => x.Length > 0));
                var key = sel.IsShared ? "COLA" : "SNMP";
                int kw = TextRenderer.MeasureText(key, fKey).Width + S(8);
                TextRenderer.DrawText(g, key, fKey, new Rectangle(tx, S(59), kw, S(16)), Theme.Muted, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
                TextRenderer.DrawText(g, id.Length > 0 ? id : "sin nombre ni ubicación", fBody, new Rectangle(tx + kw, S(59), tw - kw, S(16)), Theme.Muted, flags | TextFormatFlags.VerticalCenter);

                TextRenderer.DrawText(g, ActionText(sel), fBody, new Rectangle(tx, S(78), tw, S(16)), sel.Failed ? Theme.Red : sel.Detected ? Theme.Black : Theme.Muted, flags);
            }

            // pie: recuento + estado
            int ok = list.Items.Count(x => x.Detected), bad = list.Items.Count(x => x.Failed);
            int y = detail.Height - S(26);
            using (var b = new SolidBrush(Theme.Line)) g.FillRectangle(b, pad, y - S(8), w - 2 * pad, 1);
            int fx = pad;
            foreach (var (st, text) in new[] { (ScanState.Printer, $"{ok} online"), (ScanState.Unreachable, $"{bad} offline") })
            {
                DrawDot(g, st, new Rectangle(fx, y + S(3), S(10), S(10)));
                fx += S(16);
                TextRenderer.DrawText(g, text, fFoot, new Point(fx, y + S(1)), Theme.Black, TextFormatFlags.NoPadding);
                fx += TextRenderer.MeasureText(text, fFoot).Width + S(16);
            }
            TextRenderer.DrawText(g, Status, fFoot, new Rectangle(fx + S(4), y + S(1), w - pad - fx - S(4), S(16)), Theme.Muted, flags);
        }

        /// <summary>Que hara INSTALAR o, si no se detecta, por que.</summary>
        static string ActionText(ScanEntry e)
        {
            var r = e.Result;
            switch (e.State)
            {
                case ScanState.Pending: return "Pendiente";
                case ScanState.Checking: return "Comprobando…";
                case ScanState.Printer:
                    var extra = r.Hint.Length > 0 ? "  ·  " + r.Hint : "";
                    if (e.IsShared) return "Instalar: conectar cola compartida (driver del servidor)" + extra;
                    if (e.Brand == "Ricoh") return $"Instalar: {(RicohModels.Detect(r.Description) ?? RicohModels.Universal).DriverName}  →  «{e.QueueName}»";
                    if (e.Brand == "Canon") return "Instalar: asistente Canon Generic Plus PCL6  ·  IP al portapapeles";
                    return "Marca no soportada (solo Ricoh / Canon)";
                default: return r?.Hint ?? "";
            }
        }

        /// <summary>Texto corto de la columna modelo / estado.</summary>
        internal static string StateText(ScanEntry e) =>
            e.State == ScanState.Checking ? "…" : e.State == ScanState.Pending ? "" : e.Result.Model.Length > 0 ? e.Result.Model : "impresora";

        /// <summary>Estado como esfera: degradado con la luz arriba a la izquierda, borde oscuro y brillo pequeño.</summary>
        internal static void DrawDot(Graphics g, ScanState st, Rectangle dot)
        {
            var old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (st == ScanState.Printer || st == ScanState.Unreachable || st == ScanState.NotPrinter)
            {
                var c = st == ScanState.Printer ? Theme.Green : Theme.Red;
                using (var b = new SolidBrush(Color.FromArgb(24, 0, 0, 0))) g.FillEllipse(b, dot.X + dot.Width * .14f, dot.Bottom - dot.Height * .1f, dot.Width * .72f, dot.Height * .2f);
                using (var path = new GraphicsPath())
                {
                    path.AddEllipse(dot);
                    using (var b = new PathGradientBrush(path))
                    {
                        b.CenterPoint = new PointF(dot.X + dot.Width * .36f, dot.Y + dot.Height * .32f);
                        b.CenterColor = Mix(c, Color.White, .45f);
                        b.SurroundColors = new[] { Mix(c, Color.Black, .22f) };
                        g.FillPath(b, path);
                    }
                }
                using (var b = new SolidBrush(Color.FromArgb(170, 255, 255, 255)))
                    g.FillEllipse(b, dot.X + dot.Width * .24f, dot.Y + dot.Height * .16f, dot.Width * .30f, dot.Height * .22f);
            }
            else using (var p = new Pen(st == ScanState.Checking ? Theme.Muted : Theme.Line, Math.Max(1, dot.Width / 6))) g.DrawEllipse(p, dot);
            g.SmoothingMode = old;
        }

        static Color Mix(Color a, Color b, float t) =>
            Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));

        void UpdateDetail()
        {
            var sel = list.Selected;
            btnInstall.Enabled = sel != null && sel.CanInstall;
            btnRetry.Enabled = sel != null && sel.State != ScanState.Checking;
            btnWeb.Enabled = sel?.Result != null && sel.Result.Ports.Contains(80);
            btnCopy.Enabled = sel != null;
            detail.Invalidate();
        }

        void Redraw() => dirty = true;

        async Task CheckOne(ScanEntry e, bool quick)
        {
            e.State = ScanState.Checking;
            Redraw();
            try
            {
                e.Result = e.IsShared ? await NetworkScan.CheckShared(e.Ip) : await NetworkScan.Check(e.Ip, quick, CancellationToken.None);
                e.State = e.Result.State;
            }
            catch { e.Result = new ScanResult { State = ScanState.Unreachable, Model = "error", Hint = "Error al comprobar." }; e.State = ScanState.Unreachable; }
            Redraw();
        }

        async void CheckDirectory()
        {
            if (checkingDirectory) return;
            var entries = list.Items.Where(x => x.Group == DirectoryGroup).ToList();
            if (entries.Count == 0) return;
            checkingDirectory = true;
            btnDir.Enabled = false;
            dirStatus = "directorio…";
            await Task.WhenAll(entries.Select(x => CheckOne(x, quick: false)));
            btnDir.Enabled = true;
            checkingDirectory = false;
            dirStatus = $"directorio {entries.Count(x => x.Detected)}/{entries.Count}";
            Redraw();
        }

        async void ScanRange()
        {
            if (rangeCts != null) { rangeCts.Cancel(); return; }
            List<string> ips;
            try { ips = NetworkScan.ParseRange(fRange.Box.Text); }
            catch (FormatException ex) { MessageBox.Show(this, ex.Message + "\n\nEjemplos: 192.168.4.1-254 · 192.168.4.0/24 · 192.168.4.10-192.168.4.80", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

            string group = fRange.Box.Text.Trim();
            list.Items.RemoveAll(x => x.Group == group);
            if (list.Selected != null && !list.Items.Contains(list.Selected)) list.Select(null);
            rangeCts = new CancellationTokenSource();
            var ct = rangeCts.Token;
            btnScan.Text = "Detener";
            btnScan.Invalidate();
            progress.Value = 0;
            progress.Visible = true;
            int done = 0, alive = 0, found = 0;
            var gate = new SemaphoreSlim(Parallel);
            var sw = Stopwatch.StartNew();
            var byIp = list.Items.Where(x => x.Group == DirectoryGroup).GroupBy(x => x.Ip).ToDictionary(x => x.Key, x => x.First());

            async Task one(string ip)
            {
                try
                {
                    await gate.WaitAsync(ct);
                    try
                    {
                        var r = await NetworkScan.Check(ip, quick: true, ct);
                        if (r.State != ScanState.Unreachable) alive++;
                        if (r.State == ScanState.Printer)
                        {
                            found++;
                            byIp.TryGetValue(ip, out var dir);
                            Insert(new ScanEntry { Ip = ip, Group = group, Directory = dir?.Directory, Result = r, State = r.State });
                            // la del directorio tambien queda en verde sin esperar a su comprobacion
                            if (dir != null && dir.State != ScanState.Printer) { dir.Result = r; dir.State = r.State; }
                        }
                    }
                    finally { gate.Release(); }
                }
                catch (OperationCanceledException) { }
                catch { }
                done++;
                progress.Value = done * 100 / ips.Count;
                rangeStatus = $"{done}/{ips.Count} IPs · {alive} hosts · {found} impresoras";
                Redraw();
            }

            await Task.WhenAll(ips.Select(one));
            rangeStatus = (ct.IsCancellationRequested ? "detenido · " : "") + $"{ips.Count} IPs en {sw.Elapsed.TotalSeconds:0.0} s · {alive} hosts · {found} impresoras";
            progress.Visible = false;
            rangeCts = null;
            btnScan.Text = "Escanear";
            btnScan.Invalidate();
            Redraw();
        }

        /// <summary>Inserta en su sitio: directorio primero (orden del fichero), luego cada rango ordenado por IP.</summary>
        void Insert(ScanEntry e)
        {
            uint ip = NetworkScan.ToUInt(e.Ip);
            int i = list.Items.FindIndex(x => x.Group == e.Group && NetworkScan.ToUInt(x.Ip) > ip);
            if (i < 0)
            {
                int last = list.Items.FindLastIndex(x => x.Group == e.Group);
                i = last < 0 ? list.Items.Count : last + 1;
            }
            list.Items.Insert(i, e);
        }
    }

    /// <summary>Lista pintada a mano: cabecera de columnas fija, grupos (oficina / rango) y filas con estado.</summary>
    sealed class ScanList : Painted
    {
        public readonly List<ScanEntry> Items = new List<ScanEntry>();
        public ScanEntry Selected { get; private set; }
        public event Action<ScanEntry> SelectionChanged, Activated;
        public string EmptyText = "";
        ScanEntry hoverItem;
        int scrollY, contentHeight;
        readonly List<(Rectangle rect, ScanEntry e)> hits = new List<(Rectangle, ScanEntry)>();
        readonly Font fGroup = Theme.Strong(8.25f), fCol = Theme.Strong(7.5f), fRow = Theme.Sans(9.25f), fModel = Theme.Sans(8.5f), fIp = Theme.Mono(8.75f), fEmpty = Theme.Sans(9.5f);
        int RowH => S(32);
        int ColH => S(26);
        int MaxScroll => Math.Max(0, contentHeight - (Height - ColH));

        public ScanList() { TabStop = true; }

        public void Select(ScanEntry e)
        {
            if (e == Selected) return;
            Selected = e;
            EnsureVisible(e);
            Invalidate();
            SelectionChanged?.Invoke(e);
        }

        void EnsureVisible(ScanEntry e)
        {
            var hit = hits.FirstOrDefault(h => h.e == e);
            if (hit.e == null) return;
            if (hit.rect.Top < ColH) scrollY -= ColH - hit.rect.Top;
            else if (hit.rect.Bottom > Height) scrollY += hit.rect.Bottom - Height;
            scrollY = Math.Max(0, Math.Min(MaxScroll, scrollY));
        }

        // agrupado: directorio por oficina, rangos por rango
        IEnumerable<IGrouping<string, ScanEntry>> Groups() =>
            Items.GroupBy(i => i.Group == "Directorio" && i.Directory != null ? i.Directory.Office : "Red " + i.Group);

        // columnas: equipo | modelo / estado | latencia | direccion
        (int name, int model, int lat, int ip) Columns(int x, int w)
        {
            int ipW = S(170), latW = S(52), avail = w - x - ipW - latW;
            int nameW = (int)(avail * .44);
            return (x, x + nameW, x + avail, w - ipW);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Paper);
            hits.Clear();
            int pad = S(24), w = Width - S(8) - pad;
            var c = Columns(pad + S(22), w);
            if (Items.Count == 0)
            {
                TextRenderer.DrawText(g, EmptyText, fEmpty, new Rectangle(pad, S(20), Width - 2 * pad, S(40)), Theme.Muted, TextFormatFlags.Left | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
                return;
            }
            var flags = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding;
            var right = TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding;

            g.SetClip(new Rectangle(0, ColH, Width, Height - ColH));
            int y = ColH + S(6) - scrollY;
            foreach (var grp in Groups())
            {
                var gr = new Rectangle(pad, y, w - pad, S(30));
                TextRenderer.DrawText(g, Theme.Caps(grp.Key), fGroup, gr, Theme.Black, flags);
                TextRenderer.DrawText(g, $"{grp.Count(x => x.Detected)}/{grp.Count()}", fGroup, gr, Theme.Muted, right);
                using (var p = new Pen(Theme.Black)) g.DrawLine(p, pad, y + S(29), w, y + S(29));
                y += S(30);
                foreach (var it in grp)
                {
                    var r = new Rectangle(0, y, w + S(8), RowH);
                    if (r.Bottom > ColH) hits.Add((r, it));
                    if (r.Bottom >= ColH && r.Top <= Height) PaintRow(g, it, r, pad, w, c, flags, right);
                    y += RowH;
                }
                y += S(12);
            }
            contentHeight = y + scrollY - ColH;
            g.ResetClip();
            if (scrollY > MaxScroll) { scrollY = MaxScroll; Invalidate(); }

            // cabecera de columnas fija
            using (var b = new SolidBrush(Theme.Paper)) g.FillRectangle(b, 0, 0, Width, ColH);
            using (var b = new SolidBrush(Theme.Line)) g.FillRectangle(b, pad, ColH - 1, w - pad, 1);
            var muted = Theme.Muted;
            TextRenderer.DrawText(g, "EQUIPO", fCol, new Rectangle(c.name, 0, c.model - c.name, ColH), muted, flags);
            TextRenderer.DrawText(g, "MODELO / ESTADO", fCol, new Rectangle(c.model, 0, c.lat - c.model, ColH), muted, flags);
            TextRenderer.DrawText(g, "LAT.", fCol, new Rectangle(c.lat, 0, c.ip - c.lat, ColH), muted, right);
            TextRenderer.DrawText(g, "DIRECCIÓN", fCol, new Rectangle(c.ip, 0, w - c.ip, ColH), muted, right);

            if (MaxScroll > 0)
            {
                int view = Height - ColH;
                int barH = Math.Max(S(24), view * view / (contentHeight + 1));
                int barY = ColH + (view - barH) * scrollY / MaxScroll;
                using (var b = new SolidBrush(Theme.Line)) g.FillRectangle(b, Width - S(5), ColH, S(2), view);
                using (var b = new SolidBrush(Theme.Muted)) g.FillRectangle(b, Width - S(5), barY, S(2), barH);
            }
        }

        void PaintRow(Graphics g, ScanEntry it, Rectangle r, int pad, int w, (int name, int model, int lat, int ip) c, TextFormatFlags flags, TextFormatFlags right)
        {
            bool sel = it == Selected;
            if (sel || it == hoverItem) using (var b = new SolidBrush(sel ? Color.FromArgb(240, 240, 240) : Theme.Hover)) g.FillRectangle(b, r);
            if (sel) using (var b = new SolidBrush(Theme.Black)) g.FillRectangle(b, 0, r.Y, S(3), r.Height);
            using (var p = new Pen(Color.FromArgb(236, 236, 236))) g.DrawLine(p, pad, r.Bottom - 1, w, r.Bottom - 1);

            ScannerForm.DrawDot(g, it.State, new Rectangle(pad + S(1), r.Y + r.Height / 2 - S(5), S(11), S(11)));
            var label = it.Label;
            TextRenderer.DrawText(g, label, fRow, new Rectangle(c.name, r.Y, c.model - c.name - S(10), r.Height), label == "Sin nombre" ? Theme.Muted : Theme.Black, flags);
            TextRenderer.DrawText(g, ScannerForm.StateText(it), fModel, new Rectangle(c.model, r.Y, c.lat - c.model - S(6), r.Height), it.Failed ? Theme.Red : Theme.Muted, flags);
            if (it.Result?.PingMs != null)
                TextRenderer.DrawText(g, it.Result.PingMs + " ms", fModel, new Rectangle(c.lat, r.Y, c.ip - c.lat, r.Height), Theme.Muted, right);
            TextRenderer.DrawText(g, it.Ip, fIp, new Rectangle(c.ip, r.Y, w - c.ip, r.Height), it.Failed ? Theme.Red : it.Detected ? Theme.Black : Theme.Muted, right | TextFormatFlags.EndEllipsis);
        }

        ScanEntry HitTest(Point p) => p.Y < ColH ? null : hits.FirstOrDefault(h => h.rect.Contains(p)).e;

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            int next = Math.Max(0, Math.Min(MaxScroll, scrollY - Math.Sign(e.Delta) * RowH * 3));
            if (next != scrollY) { scrollY = next; Invalidate(); }
            base.OnMouseWheel(e);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            var h = HitTest(e.Location);
            if (h != hoverItem) { hoverItem = h; Cursor = h != null ? Cursors.Hand : Cursors.Default; Invalidate(); }
            base.OnMouseMove(e);
        }

        protected override void OnMouseLeave(EventArgs e) { hoverItem = null; base.OnMouseLeave(e); }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            Focus();
            var h = HitTest(e.Location);
            if (h != null) Select(h);
            base.OnMouseDown(e);
        }

        protected override void OnMouseDoubleClick(MouseEventArgs e)
        {
            var h = HitTest(e.Location);
            if (h != null) Activated?.Invoke(h);
            base.OnMouseDoubleClick(e);
        }

        protected override bool IsInputKey(Keys k) => k == Keys.Up || k == Keys.Down || base.IsInputKey(k);

        protected override void OnKeyDown(KeyEventArgs e)
        {
            var order = Groups().SelectMany(x => x).ToList();
            if (order.Count == 0) return;
            int i = Selected == null ? -1 : order.IndexOf(Selected);
            if (e.KeyCode == Keys.Down) Select(order[Math.Min(order.Count - 1, i + 1)]);
            else if (e.KeyCode == Keys.Up) Select(order[Math.Max(0, i - 1)]);
            else if (e.KeyCode == Keys.Enter && Selected != null) Activated?.Invoke(Selected);
            base.OnKeyDown(e);
        }
    }
}
