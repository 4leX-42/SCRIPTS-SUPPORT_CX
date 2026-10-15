using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace InstaladorImpresoras
{
    public sealed class MainForm : Form
    {
        static readonly string[] VirtualPrinters = { "PDF", "OneNote", "Fax", "XPS", "AnyDesk", "PDFelement", "Print to" };

        readonly Panel header = new Panel();
        readonly Panel body = new Panel();
        readonly Label lblClose = new Label(), lblMin = new Label();
        string hTag = "", hTitle = "", hSub = "";
        bool closeAllowed = true;
        readonly string logPath;
        readonly string workDir;
        readonly string version = typeof(MainForm).Assembly.GetName().Version.ToString(3);

        // pagina Ricoh
        readonly List<CheckRow> printerRows = new List<CheckRow>();
        CheckRow chkNew;
        LineField fIp, fName;
        Label lblProbe;
        FlatBtn btnInstall;

        // pagina progreso
        Label lblStep, lblPct;
        ThinProgress progress;
        RichTextBox logBox;
        FlatBtn btnClose;
        readonly List<string> summary = new List<string>();

        int S(int px) => (int)Math.Round(px * DeviceDpi / 96.0);

        public MainForm()
        {
            Text = "PrintDeploy";
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            FormBorderStyle = FormBorderStyle.None;
            AutoScaleMode = AutoScaleMode.None;
            Font = Theme.Sans(9.5f);
            BackColor = Theme.Paper;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(S(780), S(660));
            Padding = new Padding(1);
            KeyPreview = true;
            KeyDown += (s, e) => { if (e.KeyCode == Keys.Escape && closeAllowed) Close(); };

            var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PrintDeploy", "Logs");
            Directory.CreateDirectory(logDir);
            logPath = Path.Combine(logDir, $"instalacion_{stamp}.log");
            workDir = Path.Combine(Path.GetTempPath(), "PrintDeploy_" + stamp);

            BuildHeader();
            body.Dock = DockStyle.Fill;
            body.BackColor = Theme.Paper;
            body.Padding = new Padding(S(36), S(28), S(36), S(24));
            Controls.Add(body);
            Controls.Add(header);

            FormClosing += (s, e) =>
            {
                if (!closeAllowed) { e.Cancel = true; return; }
                try { if (Directory.Exists(workDir)) Directory.Delete(workDir, true); } catch { }
            };
            ShowChooser();
        }

        // ---------- ventana sin bordes: sombra, borde, arrastre ----------
        protected override CreateParams CreateParams
        {
            get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; cp.Style |= 0x20000; return cp; } // CS_DROPSHADOW + WS_MINIMIZEBOX
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (var p = new Pen(Theme.Black)) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }

        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, int w, int l);

        void BuildHeader()
        {
            header.Dock = DockStyle.Top;
            header.Height = S(118);
            header.BackColor = Theme.Black;
            typeof(Panel).GetProperty("DoubleBuffered", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).SetValue(header, true);
            header.MouseDown += (s, e) => { if (e.Button == MouseButtons.Left) { ReleaseCapture(); SendMessage(Handle, 0xA1, 2, 0); } };
            header.Paint += (s, e) =>
            {
                var g = e.Graphics;
                int x = S(36);
                using (var b = new SolidBrush(Theme.Red)) g.FillRectangle(b, x - S(2), S(20), S(3), S(14));
                Theme.DrawGradientText(g, Theme.Caps("IT // " + hTag), Theme.Mono(8f, FontStyle.Bold), new Point(x + S(8), S(21)), Theme.RedOnDark, Theme.Paper);
                TextRenderer.DrawText(g, hTitle, Theme.Serif(20f), new Point(x - S(2), S(42)), Theme.Paper, TextFormatFlags.NoPadding);
                TextRenderer.DrawText(g, hSub, Theme.Sans(9.5f), new Point(x, S(82)), Color.FromArgb(205, 205, 207), TextFormatFlags.NoPadding);
                using (var b = new SolidBrush(Theme.Red)) g.FillRectangle(b, 0, header.Height - S(3), S(120), S(3));
                using (var b = new SolidBrush(Color.FromArgb(62, 62, 64))) g.FillRectangle(b, S(120), header.Height - 1, header.Width, 1);
            };

            foreach (var (lbl, text, act) in new[] { (lblClose, "✕", (Action)(() => Close())), (lblMin, "—", (Action)(() => WindowState = FormWindowState.Minimized)) })
            {
                lbl.Text = text;
                lbl.Font = Theme.Mono(10f);
                lbl.ForeColor = Color.FromArgb(205, 205, 207);
                lbl.BackColor = Theme.Black;
                lbl.TextAlign = ContentAlignment.MiddleCenter;
                lbl.Size = new Size(S(46), S(34));
                lbl.Cursor = Cursors.Hand;
                lbl.MouseEnter += (s, e) => { lbl.BackColor = lbl == lblClose ? Theme.Red : Color.FromArgb(56, 56, 58); lbl.ForeColor = Theme.Paper; };
                lbl.MouseLeave += (s, e) => { lbl.BackColor = Theme.Black; lbl.ForeColor = Color.FromArgb(205, 205, 207); };
                lbl.Click += (s, e) => act();
                header.Controls.Add(lbl);
            }
            // boton del directorio de impresoras por oficina
            var btnDir = new FlatBtn("Impresoras ▾", primary: false) { Size = new Size(S(170), S(34)), OnDark = true, TabStop = false };
            btnDir.Click += (s, e) => ShowDirectory(btnDir);
            header.Controls.Add(btnDir);

            header.Resize += (s, e) =>
            {
                lblClose.Location = new Point(header.Width - lblClose.Width - 1, 1);
                lblMin.Location = new Point(lblClose.Left - lblMin.Width, 1);
                btnDir.Location = new Point(header.Width - btnDir.Width - S(36), S(58));
            };
        }

        void ShowDirectory(Control anchor)
        {
            List<OfficePrinter> items;
            try { items = PrinterDirectory.Load(); }
            catch (Exception ex) { Warn("No se pudo leer el directorio de impresoras:\n" + ex.Message); return; }
            if (items.Count == 0)
            {
                Warn("No hay directorio de impresoras.\n\nCree un fichero oficinas.txt (formato: Oficina | Ubicación | Marca | IP) en:\n\n· " +
                     string.Join("\n· ", PrinterDirectory.ExternalPaths));
                return;
            }
            var popup = new DirectoryPopup(items, UseDirectoryPrinter);
            var pt = anchor.PointToScreen(new Point(anchor.Width, anchor.Height + S(6)));
            popup.Location = new Point(pt.X - popup.Width, pt.Y);
            popup.Show(this);
        }

        /// <summary>Clic en el directorio: copia la IP y, en la pantalla Ricoh, la rellena y la comprueba.</summary>
        async void UseDirectoryPrinter(OfficePrinter p)
        {
            try { Clipboard.SetText(p.Ip); } catch { }
            bool onRicohPage = fIp != null && !fIp.IsDisposed && fIp.FindForm() == this;
            if (onRicohPage && !p.Brand.Equals("Canon", StringComparison.OrdinalIgnoreCase))
            {
                chkNew.Checked = true;
                fIp.Box.Text = p.Ip;
                var name = "Ricoh " + p.Office + (p.Location.Length > 0 ? " " + p.Location : "");
                fName.Box.Text = name.Length > 60 ? name.Substring(0, 60) : name;
                await ProbeNewIp(interactive: false);
            }
            else
            {
                MessageBox.Show(this, $"{p.Office} · {p.Label}\n\nIP {p.Ip} copiada al portapapeles.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        void SetHeader(string tag, string title, string sub)
        {
            hTag = tag; hTitle = title; hSub = sub;
            header.Invalidate();
        }

        Label Caption(string text, Color? color = null) => new Label
        {
            Text = Theme.Caps(text), Font = Theme.Mono(7.5f, FontStyle.Bold), ForeColor = color ?? Theme.Muted,
            AutoSize = false, Dock = DockStyle.Top, Height = S(24), TextAlign = ContentAlignment.BottomLeft,
        };

        Panel Gap(int h) => new Panel { Dock = DockStyle.Top, Height = S(h), BackColor = Theme.Paper };

        Panel ButtonBar(params FlatBtn[] buttons)
        {
            var bar = new Panel { Dock = DockStyle.Bottom, Height = S(48), BackColor = Theme.Paper };
            int x = 0;
            foreach (var b in buttons)
            {
                b.Size = new Size(S(160), S(42));
                b.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
                bar.Controls.Add(b);
            }
            bar.Layout += (s, e) =>
            {
                x = bar.Width;
                foreach (var b in buttons) { x -= b.Width; b.Location = new Point(x, bar.Height - b.Height); x -= S(12); }
            };
            return bar;
        }

        Label Footer(string text) => new Label
        {
            Text = text, Font = Theme.Mono(7.5f), ForeColor = Color.FromArgb(130, 130, 132),
            Dock = DockStyle.Bottom, Height = S(22), TextAlign = ContentAlignment.BottomLeft, AutoEllipsis = true,
        };

        // ================= 01: elegir marca =================
        void ShowChooser()
        {
            body.Controls.Clear();
            AcceptButton = null;
            SetHeader("Print Deployment", "PrintDeploy", "Despliegue y reparación de drivers de impresión. Seleccione el fabricante.");

            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, BackColor = Theme.Paper, Margin = Padding.Empty };
            grid.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
            grid.RowStyles.Add(new RowStyle(SizeType.Percent, 50));

            var ricoh = new Card("01 — RICOH", "Ricoh · " + RicohModels.Names,
                "Detecta el modelo automáticamente e instala su driver oficial. Limpia controladores erróneos, reinstala las colas existentes y habilita la bandeja bypass.")
            { Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, S(16)) };
            var canon = new Card("02 — CANON", "Canon · todas las multifunción",
                "Asistente oficial Canon Generic Plus PCL6. Si indica que ya existe una versión posterior, acepte y continúe.")
            { Dock = DockStyle.Fill, Margin = new Padding(0) };
            ricoh.Click += (s, e) => ShowRicoh();
            canon.Click += async (s, e) => await RunCanon();
            grid.Controls.Add(ricoh, 0, 0);
            grid.Controls.Add(canon, 0, 1);

            body.Controls.Add(grid);
            body.Controls.Add(Footer($"v{version}  ·  registro: {logPath}"));
        }

        // ================= 02: opciones Ricoh =================
        void ShowRicoh()
        {
            body.Controls.Clear();
            printerRows.Clear();
            SetHeader("Ricoh", "Configuración", "Las colas marcadas se desinstalan, se limpian y se recrean con el mismo nombre e IP.");

            // lista de impresoras instaladas
            var list = new Panel { Dock = DockStyle.Top, Height = S(32 + 4 * 40), AutoScroll = true, BackColor = Theme.Paper };
            var rows = new List<Control>();
            var head = new CheckRow { Header = true, Columns = new[] { "Impresora", "Driver actual", "Puerto / IP" }, Widths = new[] { .36f, .38f, .26f }, Dock = DockStyle.Top, Height = S(32) };
            foreach (var p in GetPrinters())
            {
                var row = new CheckRow
                {
                    Columns = new[] { p.Name, p.Driver, p.Host ?? p.Port }, Widths = head.Widths, Tag = p, Dock = DockStyle.Top, Height = S(40),
                    Checked = p.Name.IndexOf("ricoh", StringComparison.OrdinalIgnoreCase) >= 0 || p.Driver.IndexOf("ricoh", StringComparison.OrdinalIgnoreCase) >= 0,
                };
                printerRows.Add(row);
                rows.Add(row);
            }
            if (printerRows.Count == 0)
                rows.Add(new Label { Text = "No hay impresoras de red instaladas en este equipo.", ForeColor = Theme.Muted, Dock = DockStyle.Top, Height = S(40), TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(S(14), 0, 0, 0) });
            for (int i = rows.Count - 1; i >= 0; i--) list.Controls.Add(rows[i]);
            list.Controls.Add(head);

            // nueva por IP
            chkNew = new CheckRow { Columns = new[] { "Agregar una Ricoh nueva por IP  ·  modelo autodetectado" }, Dock = DockStyle.Top, Height = S(40), Checked = printerRows.Count == 0 };
            var fields = new TableLayoutPanel { Dock = DockStyle.Top, Height = S(56), ColumnCount = 4, BackColor = Theme.Paper, Padding = new Padding(S(42), 0, 0, 0) };
            fields.RowCount = 1;
            fields.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, S(180)));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, S(24)));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, S(220)));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            fIp = new LineField("Dirección IP", mono: true) { Dock = DockStyle.Fill, Margin = Padding.Empty };
            fName = new LineField("Nombre de la cola", mono: false) { Dock = DockStyle.Fill, Margin = Padding.Empty };
            fName.Box.Text = "Ricoh";
            var btnProbe = new FlatBtn("Comprobar", primary: false) { Size = new Size(S(150), S(36)), Anchor = AnchorStyles.Left | AnchorStyles.Top, Margin = new Padding(S(24), S(16), 0, 0) };
            fields.Controls.Add(fIp, 0, 0);
            fields.Controls.Add(new Panel { BackColor = Theme.Paper }, 1, 0);
            fields.Controls.Add(fName, 2, 0);
            fields.Controls.Add(btnProbe, 3, 0);
            lblProbe = new Label { Dock = DockStyle.Top, Height = S(26), Font = Theme.Mono(8.5f), ForeColor = Theme.Muted, Padding = new Padding(S(42), S(6), 0, 0) };

            EventHandler toggle = (s, e) => { fIp.Box.Enabled = fName.Box.Enabled = btnProbe.Enabled = chkNew.Checked; if (!chkNew.Checked) SetProbe("", Theme.Muted); };
            chkNew.CheckedChanged += toggle;
            toggle(null, null);
            fIp.Box.TextChanged += (s, e) => SetProbe("", Theme.Muted);
            btnProbe.Click += async (s, e) => await ProbeNewIp(interactive: false);

            btnInstall = new FlatBtn("Instalar", primary: true);
            var btnBack = new FlatBtn("Atrás", primary: false);
            btnInstall.Click += async (s, e) => await StartRicoh();
            btnBack.Click += (s, e) => ShowChooser();

            body.Controls.Add(lblProbe);
            body.Controls.Add(fields);
            body.Controls.Add(chkNew);
            body.Controls.Add(Caption("Nueva impresora"));
            body.Controls.Add(Gap(14));
            body.Controls.Add(list);
            body.Controls.Add(Caption("Impresoras en este equipo"));
            body.Controls.Add(ButtonBar(btnInstall, btnBack));
        }

        sealed class PrinterInfo { public string Name, Driver, Port, Host; }

        static List<PrinterInfo> GetPrinters()
        {
            var hosts = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (var q = new ManagementObjectSearcher("SELECT Name, HostAddress FROM Win32_TCPIPPrinterPort"))
                    foreach (ManagementObject o in q.Get()) hosts[(string)o["Name"]] = (string)o["HostAddress"];
            }
            catch { }
            var list = new List<PrinterInfo>();
            using (var q = new ManagementObjectSearcher("SELECT Name, DriverName, PortName FROM Win32_Printer"))
                foreach (ManagementObject o in q.Get())
                {
                    var p = new PrinterInfo { Name = (string)o["Name"], Driver = (string)o["DriverName"] ?? "", Port = (string)o["PortName"] ?? "" };
                    if (VirtualPrinters.Any(v => p.Name.IndexOf(v, StringComparison.OrdinalIgnoreCase) >= 0 || p.Driver.IndexOf(v, StringComparison.OrdinalIgnoreCase) >= 0)) continue;
                    if (p.Name.StartsWith(@"\\")) continue; // colas compartidas de servidor
                    hosts.TryGetValue(p.Port, out p.Host);
                    list.Add(p);
                }
            return list.OrderBy(p => p.Name).ToList();
        }

        /// <summary>Comprueba la IP nueva y detecta el modelo. Devuelve el modelo a instalar o null si no se debe continuar.</summary>
        async Task<RicohModel> ProbeNewIp(bool interactive)
        {
            var ip = fIp.Box.Text.Trim();
            if (!IPAddress.TryParse(ip, out var addr) || addr.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork || ip.Count(c => c == '.') != 3)
            {
                SetProbe("✖  IP no válida", Theme.Red);
                if (interactive) Warn("La IP indicada no es válida.\nEjemplo: 192.168.1.50");
                return null;
            }
            SetProbe("…  comprobando " + ip, Theme.Muted);
            UseWaitCursor = true;
            var r = await Task.Run(() => PrinterProbe.Probe(ip));
            UseWaitCursor = false;
            switch (r.Status)
            {
                case ProbeStatus.RicohTarget:
                    SetProbe($"✔  Ricoh {r.Model.Display} detectada  →  driver {r.Model.DriverName}", Theme.Black);
                    if (fName.Box.Text.Trim().Length == 0 || fName.Box.Text.StartsWith("Ricoh IM ", StringComparison.OrdinalIgnoreCase))
                        fName.Box.Text = "Ricoh " + r.Model.Display;
                    return r.Model;
                case ProbeStatus.RicohOtherModel:
                case ProbeStatus.NotPrinter:
                    // sin preguntar: modelo no identificado -> driver universal Ricoh
                    SetProbe($"✔  Modelo sin driver específico  →  driver {RicohModels.Universal.DriverName}", Theme.Black);
                    if (fName.Box.Text.Trim().Length == 0 || fName.Box.Text.StartsWith("Ricoh IM ", StringComparison.OrdinalIgnoreCase))
                        fName.Box.Text = "Ricoh";
                    return RicohModels.Universal;
                default:
                    SetProbe("✖  " + (r.Status == ProbeStatus.Unreachable ? "Sin respuesta en " + ip : "No es una Ricoh: " + r.Description), Theme.Red);
                    if (interactive) Warn(r.Message + "\n\nNo se ha instalado nada.");
                    return null;
            }
        }

        void SetProbe(string text, Color c) { lblProbe.Text = text; lblProbe.ForeColor = c; }
        void Warn(string text) => MessageBox.Show(this, text, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        bool Ask(string text) => MessageBox.Show(this, text, Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.Yes;

        async Task StartRicoh()
        {
            var selected = printerRows.Where(r => r.Checked).Select(r => (PrinterInfo)r.Tag).ToList();
            var jobs = new List<RicohJob>();
            if (chkNew.Checked)
            {
                var newName = fName.Box.Text.Trim();
                if (newName.Length == 0) newName = "Ricoh";
                if (GetPrinters().Any(p => p.Name.Equals(newName, StringComparison.OrdinalIgnoreCase)) && !selected.Any(p => p.Name.Equals(newName, StringComparison.OrdinalIgnoreCase)))
                {
                    Warn($"Ya existe una impresora llamada \"{newName}\".\nCambie el nombre o márquela en la lista para reinstalarla.");
                    return;
                }
                btnInstall.Enabled = false;
                var model = await ProbeNewIp(interactive: true);
                btnInstall.Enabled = true;
                if (model == null) return;
                jobs.Add(new RicohJob { IsNew = true, Name = fName.Box.Text.Trim().Length > 0 ? fName.Box.Text.Trim() : newName, Ip = fIp.Box.Text.Trim(), Model = model });
            }
            if (selected.Count == 0 && jobs.Count == 0)
            {
                Warn("Marque al menos una impresora de la lista o agregue una nueva por IP.");
                return;
            }

            // colas existentes: detectar modelo por su IP; si no, por el driver actual; si no, preguntar
            var offline = new List<string>();
            btnInstall.Enabled = false;
            UseWaitCursor = true;
            var probes = new Dictionary<PrinterInfo, ProbeResult>();
            foreach (var p in selected.Where(p => p.Host != null))
                probes[p] = await Task.Run(() => PrinterProbe.Probe(p.Host));
            UseWaitCursor = false;
            btnInstall.Enabled = true;
            foreach (var p in selected)
            {
                probes.TryGetValue(p, out var r);
                if (r != null && (r.Status == ProbeStatus.Unreachable || r.Status == ProbeStatus.OtherBrand))
                    offline.Add($"· {p.Name} ({p.Host}): {(r.Status == ProbeStatus.Unreachable ? "no responde" : "no es una Ricoh")}");
                // modelo: por su IP; si no, por el driver o nombre actual; si no, driver universal (sin preguntar)
                var model = r?.Model ?? RicohModels.Detect(p.Driver) ?? RicohModels.Detect(p.Name) ?? RicohModels.Universal;
                jobs.Insert(0, new RicohJob { Name = p.Name, Model = model });
            }
            if (offline.Count > 0 && !Ask("Atención:\n\n" + string.Join("\n", offline) + "\n\nSe reinstalarán igualmente con el driver Ricoh. ¿Continuar?"))
                return;

            var confirm = new StringBuilder("Se realizarán las siguientes acciones:\n\n");
            foreach (var j in jobs.Where(j => !j.IsNew))
            {
                var p = selected.First(x => x.Name == j.Name);
                confirm.AppendLine($"· Reinstalar \"{j.Name}\" ({p.Host ?? p.Port}) con {j.Model.DriverName}");
            }
            foreach (var j in jobs.Where(j => j.IsNew)) confirm.AppendLine($"· Agregar \"{j.Name}\" en {j.Ip} con {j.Model.DriverName}");
            confirm.AppendLine("\nLos drivers antiguos que no utilice ninguna otra impresora se eliminarán.");
            if (MessageBox.Show(this, confirm.ToString(), Text, MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;

            ShowProgress("Ricoh", "Instalando", "No cierre esta ventana hasta que finalice el proceso.");
            await RunRicoh(jobs);
        }

        // ================= 03: progreso =================
        void ShowProgress(string tag, string title, string sub)
        {
            body.Controls.Clear();
            AcceptButton = null;
            SetHeader(tag, title, sub);
            summary.Clear();
            closeAllowed = false;
            lblClose.Visible = false;

            var top = new Panel { Dock = DockStyle.Top, Height = S(34), BackColor = Theme.Paper };
            lblStep = new Label { Dock = DockStyle.Fill, Font = Theme.Serif(12f), ForeColor = Theme.Black, Text = "Preparando…", TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true };
            lblPct = new Label { Dock = DockStyle.Right, Width = S(70), Font = Theme.Mono(11f, FontStyle.Bold), ForeColor = Theme.Red, Text = "000%", TextAlign = ContentAlignment.MiddleRight };
            top.Controls.Add(lblStep);
            top.Controls.Add(lblPct);
            progress = new ThinProgress { Dock = DockStyle.Top, Height = S(6) };

            logBox = new RichTextBox
            {
                Dock = DockStyle.Fill, ReadOnly = true, BackColor = Theme.Black, ForeColor = Color.FromArgb(228, 228, 230),
                BorderStyle = BorderStyle.None, Font = Theme.Mono(8.75f), DetectUrls = false, ScrollBars = RichTextBoxScrollBars.Vertical,
            };
            var logFrame = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Black, Padding = new Padding(S(16), S(12), S(8), S(12)) };
            logFrame.Controls.Add(logBox);

            btnClose = new FlatBtn("Cerrar", primary: true) { Enabled = false };
            var btnLog = new FlatBtn("Ver registro", primary: false);
            btnClose.Click += (s, e) => Close();
            btnLog.Click += (s, e) => { if (File.Exists(logPath)) Process.Start("notepad.exe", logPath); };

            body.Controls.Add(logFrame);
            body.Controls.Add(Gap(18));
            body.Controls.Add(Caption("Registro"));
            body.Controls.Add(Gap(6));
            body.Controls.Add(progress);
            body.Controls.Add(Gap(10));
            body.Controls.Add(top);
            var spacer = Gap(16); spacer.Dock = DockStyle.Bottom;
            body.Controls.Add(spacer);
            body.Controls.Add(ButtonBar(btnClose, btnLog));
        }

        void Log(string kind, string text)
        {
            if (InvokeRequired) { BeginInvoke((Action)(() => Log(kind, text))); return; }
            // sobre fondo oscuro el rojo solo marca (etiqueta); el texto va claro para que se lea
            string tag; Color tagColor, c;
            switch (kind)
            {
                case "OK":   tag = "[ OK ] "; tagColor = Color.FromArgb(150, 150, 152); c = Theme.Paper; break;
                case "WARN": tag = "[ !! ] "; tagColor = Theme.Amber; c = Color.FromArgb(240, 220, 180); break;
                case "ERR":  tag = "[ERR ] "; tagColor = Theme.RedOnDark; c = Color.FromArgb(255, 200, 205); break;
                case "STEP": tag = "▌ ";      tagColor = Theme.RedOnDark; c = Theme.Paper; break;
                default:     tag = "       "; tagColor = c = Color.FromArgb(170, 170, 172); break;
            }
            if (kind == "STEP" && logBox.TextLength > 0) logBox.AppendText("\n");
            int start = logBox.TextLength;
            logBox.AppendText(tag + text + "\n");
            var font = kind == "STEP" ? Theme.Mono(8.75f, FontStyle.Bold) : logBox.Font;
            logBox.Select(start, tag.Length);
            logBox.SelectionColor = tagColor;
            logBox.SelectionFont = font;
            logBox.Select(start + tag.Length, logBox.TextLength - start - tag.Length);
            logBox.SelectionColor = c;
            logBox.SelectionFont = font;
            logBox.Select(logBox.TextLength, 0);
            logBox.ScrollToCaret();
            try { File.AppendAllText(logPath, $"{DateTime.Now:HH:mm:ss} [{kind}] {text}\r\n", Encoding.UTF8); } catch { }
        }

        void SetStep(int pct, string text)
        {
            if (InvokeRequired) { BeginInvoke((Action)(() => SetStep(pct, text))); return; }
            progress.Value = pct;
            lblPct.Text = Math.Max(0, Math.Min(100, pct)).ToString("000") + "%";
            lblStep.Text = text;
            Log("STEP", text.ToUpperInvariant());
        }

        void Finish(bool ok, string message)
        {
            progress.Value = 100;
            progress.BarColor = ok ? Theme.Black : Theme.Red;
            lblPct.Text = ok ? "100%" : "ERR";
            closeAllowed = true;
            lblClose.Visible = true;
            btnClose.Enabled = true;
            AcceptButton = null;
            btnClose.Focus();
            lblStep.Text = ok ? "Instalación completada" : "Finalizado con errores";
            lblStep.ForeColor = ok ? Theme.Black : Theme.Red;
            SetHeader(hTag, ok ? "Completado" : "Revisión necesaria", ok ? "Puede cerrar esta ventana." : "Consulte el registro para ver el detalle del error.");
            if (summary.Count > 0)
            {
                Log("STEP", "RESUMEN");
                foreach (var s in summary) Log(s.Contains("ERROR") ? "ERR" : "OK", s);
            }
            if (message != null) { Log("LOG", ""); Log("LOG", message); }
            Activate();
            TopMost = true;
            TopMost = false;
        }

        string ExtractPayload(string resource, string folder)
        {
            var dest = Path.Combine(workDir, folder);
            if (Directory.Exists(dest)) Directory.Delete(dest, true);
            Directory.CreateDirectory(workDir);
            var zip = Path.Combine(workDir, resource);
            using (var s = typeof(MainForm).Assembly.GetManifestResourceStream(resource))
            {
                if (s == null) throw new FileNotFoundException($"Esta compilación no incluye el paquete de driver '{resource}'. Colóquelo en Payload\\ y vuelva a compilar (ver Payload\\README.md).");
                using (var f = File.Create(zip)) s.CopyTo(f);
            }
            ZipFile.ExtractToDirectory(zip, dest);
            File.Delete(zip);
            return dest;
        }

        sealed class RicohJob { public bool IsNew; public string Name, Ip; public RicohModel Model; }

        async Task RunRicoh(List<RicohJob> jobs)
        {
            int exit = -1;
            try
            {
                // extraer solo los paquetes de driver que hacen falta
                var infs = new Dictionary<RicohModel, string>();
                foreach (var m in jobs.Select(j => j.Model).Distinct())
                {
                    SetStep(2, "Preparando driver " + m.DriverName);
                    var dir = await Task.Run(() => ExtractPayload(m.Resource, Path.GetFileNameWithoutExtension(m.Resource)));
                    infs[m] = Path.Combine(dir, m.Inf);
                }
                var engine = Path.Combine(workDir, "engine.ps1");
                using (var s = typeof(MainForm).Assembly.GetManifestResourceStream("engine.ps1"))
                using (var f = File.Create(engine)) s.CopyTo(f);

                string clean(string v) => v.Replace("\t", " ").Replace("\n", " ").Replace("\r", "");
                var lines = jobs.Select(j => string.Join("\t", new[] { j.IsNew ? "N" : "E", clean(j.Name), j.Model.DriverName, infs[j.Model] }.Concat(j.IsNew ? new[] { j.Ip } : new string[0])));
                var b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(string.Join("\n", lines)));
                var args = $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{engine}\" -JobsB64 {b64}";

                exit = await Task.Run(() => RunEngine(args));
            }
            catch (Exception ex)
            {
                Log("ERR", ex.Message);
            }
            bool ok = exit == 0;
            Finish(ok, ok ? "Bandeja bypass: Imprimir > Preferencias > Bandeja de entrada > \"Bandeja bypass\"." : null);
        }

        int RunEngine(string args)
        {
            var psi = new ProcessStartInfo("powershell.exe", args)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
            };
            using (var p = new Process { StartInfo = psi })
            {
                p.OutputDataReceived += (s, e) => { if (e.Data != null) HandleEngineLine(e.Data); };
                p.ErrorDataReceived += (s, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) Log("ERR", e.Data); };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                p.WaitForExit();
                return p.ExitCode;
            }
        }

        void HandleEngineLine(string line)
        {
            var parts = line.Split(new[] { '|' }, 2);
            if (parts.Length < 2) { if (line.Trim().Length > 0) Log("LOG", line); return; }
            switch (parts[0])
            {
                case "STEP":
                    var sp = parts[1].Split(new[] { '|' }, 2);
                    SetStep(int.TryParse(sp[0], out var pct) ? pct : 0, sp.Length > 1 ? sp[1] : "");
                    break;
                case "SUMMARY":
                    lock (summary) summary.Add(parts[1]);
                    break;
                case "OK": case "WARN": case "ERR": case "LOG":
                    Log(parts[0], parts[1]);
                    break;
                default:
                    Log("LOG", line);
                    break;
            }
        }

        // ================= Canon =================
        async Task RunCanon()
        {
            ShowProgress("Canon", "Generic Plus PCL6", "Siga los pasos del asistente de Canon.");
            bool ok = false;
            try
            {
                SetStep(10, "Preparando archivos del driver Canon");
                var dir = await Task.Run(() => ExtractPayload("canon.zip", "canon"));
                SetStep(40, "Asistente de Canon en curso");
                int code = await Task.Run(() =>
                {
                    using (var p = Process.Start(new ProcessStartInfo(Path.Combine(dir, "Setup.exe")) { WorkingDirectory = dir, UseShellExecute = true }))
                    {
                        p.WaitForExit();
                        return p.ExitCode;
                    }
                });
                Log("LOG", $"Asistente de Canon finalizado (código {code}).");
                ok = true;
                SetStep(100, "Finalizado");
            }
            catch (Exception ex)
            {
                Log("ERR", ex.Message);
            }
            Finish(ok, ok ? "Si el asistente indicó una versión posterior ya instalada, no es necesaria ninguna acción adicional." : null);
        }
    }
}

