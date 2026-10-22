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
            Icon = AppIcon();
            FormBorderStyle = FormBorderStyle.None;
            AutoScaleMode = AutoScaleMode.None;
            Font = Theme.Sans(9.5f);
            BackColor = Theme.Paper;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(S(780), S(660));
            Padding = new Padding(1);
            KeyPreview = true;
            // Esc: en el resumen de una instalacion vuelve al inicio; en el inicio, sale
            KeyDown += (s, e) => { if (e.KeyCode == Keys.Escape && closeAllowed) { if (onProgress) Back(); else Close(); } };
            // inicio: 1 escaner · 2 Ricoh · 3 Canon, sin raton
            KeyDown += async (s, e) =>
            {
                if (!onChooser || !closeAllowed) return;
                if (e.KeyCode == Keys.D1 || e.KeyCode == Keys.NumPad1) ShowScanner();
                else if (e.KeyCode == Keys.D2 || e.KeyCode == Keys.NumPad2) { returnToScanner = false; ShowRicoh(); }
                else if (e.KeyCode == Keys.D3 || e.KeyCode == Keys.NumPad3) { returnToScanner = false; ShowCanon(); }
            };

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
                if (hTag.Length == 0)
                {
                    // inicio: solo la marca, en trazo fino; "Deploy" en dorado
                    var flags = TextFormatFlags.NoPadding;
                    TextRenderer.DrawText(g, "Print", fWordmark, new Point(x - S(2), S(30)), Theme.Paper, flags);
                    int pw = TextRenderer.MeasureText(g, "Print", fWordmark, Size.Empty, flags).Width;
                    TextRenderer.DrawText(g, "Deploy", fWordmark, new Point(x - S(2) + pw, S(30)), Theme.Gold, flags);
                    TextRenderer.DrawText(g, hSub, fHeadSub, new Point(x, S(80)), Theme.HeadSub, flags);
                }
                else
                {
                    Theme.DrawMark(g, hTag, fMark, new Point(x, S(20)), S);
                    TextRenderer.DrawText(g, hTitle, fHeadTitle, new Point(x - S(2), S(42)), Theme.Paper, TextFormatFlags.NoPadding);
                    TextRenderer.DrawText(g, hSub, fHeadSub, new Point(x, S(82)), Theme.HeadSub, TextFormatFlags.NoPadding);
                }
                using (var b = new SolidBrush(Color.FromArgb(56, 56, 58))) g.FillRectangle(b, 0, header.Height - 1, header.Width, 1);
            };

            foreach (var (lbl, text, act) in new[] { (lblClose, "✕", (Action)(() => Close())), (lblMin, "—", (Action)(() => WindowState = FormWindowState.Minimized)) })
            {
                lbl.Text = text;
                lbl.Font = Theme.Sans(10f);
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
            // acceso directo a "Dispositivos e impresoras"
            var lblPanel = new IconBtn(Theme.GlyphPrinter, "Dispositivos e impresoras") { Size = new Size(S(40), S(34)) };
            lblPanel.Click += (s, e) => Theme.OpenPrintersPanel();
            header.Controls.Add(lblPanel);
            // escaner de red: directorio de oficinas + busqueda por rango
            var btnDir = new FlatBtn("Escáner", primary: false) { Size = new Size(S(150), S(34)), OnDark = true, TabStop = false, Eye = true, SweepOnHover = true };
            Shown += (s, e) => btnDir.StartSweep();   // una pasada al abrir
            btnDir.Click += (s, e) => ShowScanner();
            header.Controls.Add(btnDir);

            header.Resize += (s, e) =>
            {
                lblClose.Location = new Point(header.Width - lblClose.Width - 1, 1);
                lblMin.Location = new Point(lblClose.Left - lblMin.Width, 1);
                lblPanel.Location = new Point(lblMin.Left - lblPanel.Width, 1);
                btnDir.Location = new Point(header.Width - btnDir.Width - S(36), S(58));
            };
        }

        readonly Font fMark = Theme.Strong(8.25f), fHeadTitle = Theme.Title(20f), fHeadSub = Theme.Sans(9.5f), fWordmark = Theme.Light(24f);

        /// <summary>
        /// Icono de la ventana. ExtractAssociatedIcon falla con rutas de red (\\servidor\carpeta\PrintDeploy.exe):
        /// en ese caso, sin icono propio antes que no arrancar.
        /// </summary>
        static Icon AppIcon()
        {
            try { return Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch (ArgumentException) { return null; }
        }

        ScannerForm scanner;
        bool returnToScanner, onProgress, onChooser;

        void ShowScanner()
        {
            if (scanner == null)
            {
                List<OfficePrinter> items;
                try { items = PrinterDirectory.Load(); }
                catch (Exception ex) { Warn("Error al leer oficinas.txt (el escaneo de red sigue disponible):\n" + ex.Message); items = new List<OfficePrinter>(); }
                scanner = new ScannerForm(items, InstallFromScan);
            }
            if (!scanner.Visible)
            {
                // centrado sobre la ventana principal, sin salirse de la pantalla
                var area = Screen.FromControl(this).WorkingArea;
                scanner.Location = new Point(
                    Math.Max(area.Left, Math.Min(area.Right - scanner.Width, Left + (Width - scanner.Width) / 2)),
                    Math.Max(area.Top, Math.Min(area.Bottom - scanner.Height, Top + (Height - scanner.Height) / 2)));
                scanner.Show(this);
            }
            scanner.Activate();
        }

        /// <summary>
        /// Instalar desde el escaner: IP y modelo ya detectados, sin volver a sondear.
        /// Ricoh: si ya hay una cola en esa IP se reinstala (conserva su configuracion); si no, cola nueva.
        /// Canon: asistente oficial con la IP en el portapapeles.
        /// </summary>
        async void InstallFromScan(ScanEntry e)
        {
            if (!closeAllowed) { Warn("Instalación en curso."); return; }
            try { Clipboard.SetText(e.Ip); } catch { }
            returnToScanner = true;
            if (e.Directory?.IsShared == true)
            {
                if (!ThemedDialog.Confirm(scanner, "Servidor", e.Label, $"{e.Result.Model}\n\n· Add-Printer -ConnectionName {e.Ip} (usuario actual)\n· printui /ga (todos los usuarios, al iniciar sesión)\n· Conexión previa: se elimina y se recrea", "Conectar")) return;
                scanner.Hide();
                await RunShared(e.Ip);
                return;
            }
            if (e.Brand == "Canon")
            {
                var how = CanonDriverInstalled() ? "instalado" : "paquete";
                if (!ThemedDialog.Confirm(scanner, "Canon", e.Label, $"{e.Result.Model}\n\n· Cola «{e.QueueName}» en {e.Ip}\n· {CanonDriver} ({how})\n· Cola existente en esa IP: se actualiza")) return;
                scanner.Hide();
                await RunCanonDirect(e.Ip, e.QueueName);
                return;
            }

            var model = RicohModels.Detect(e.Result.Description) ?? RicohModels.Universal;
            var printers = GetPrinters();
            var existing = printers.FirstOrDefault(p => p.Host == e.Ip);
            RicohJob job;
            string action;
            if (existing != null)
            {
                job = new RicohJob { Name = existing.Name, Model = model };
                action = $"Reinstalar «{existing.Name}» (puerto {e.Ip})";
            }
            else
            {
                var name = e.QueueName;
                if (printers.Any(p => p.Name.Equals(name, StringComparison.OrdinalIgnoreCase))) name = $"{name} ({e.Ip})";
                job = new RicohJob { IsNew = true, Name = name, Ip = e.Ip, Model = model };
                action = $"Nueva cola «{name}» · {e.Ip}";
            }
            var msg = $"{e.Result.Model}\n\n· {action}\n· Driver: {model.DriverName}\n· Drivers Ricoh sin uso: se eliminan";
            if (!ThemedDialog.Confirm(scanner, "Ricoh", e.Label, msg)) return;
            scanner.Hide();
            ShowProgress("Ricoh", "Instalando", "No cerrar hasta finalizar.");
            await RunRicoh(new List<RicohJob> { job });
        }

        void SetHeader(string tag, string title, string sub)
        {
            hTag = tag; hTitle = title; hSub = sub;
            header.Invalidate();
        }

        // Ritmo vertical unico para todas las pantallas:
        //   titulo de seccion (texto + filete) -> SectionGap -> contenido -> BlockGap -> siguiente seccion
        const int SectionGap = 12, BlockGap = 28;

        /// <summary>Titulo de seccion: etiqueta en mayusculas con un filete debajo y separacion fija con el contenido.</summary>
        Panel Section(string text)
        {
            var p = new Panel { Dock = DockStyle.Top, Height = S(26 + SectionGap), BackColor = Theme.Paper };
            var font = Theme.Strong(8.25f);
            p.Paint += (s, e) =>
            {
                TextRenderer.DrawText(e.Graphics, Theme.Caps(text), font, new Point(0, 0), Theme.Muted, TextFormatFlags.NoPadding);
                using (var b = new SolidBrush(Theme.Line)) e.Graphics.FillRectangle(b, 0, S(24), p.Width, 1);
                using (var b = new SolidBrush(Theme.GoldDeep)) e.Graphics.FillRectangle(b, 0, S(23), S(24), S(2));
            };
            return p;
        }

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
            Text = text, Font = Theme.Sans(8f), ForeColor = Color.FromArgb(130, 130, 132),
            Dock = DockStyle.Bottom, Height = S(22), TextAlign = ContentAlignment.BottomLeft, AutoEllipsis = true,
        };

        // ================= 01: elegir marca =================
        void ShowChooser()
        {
            body.Controls.Clear();
            AcceptButton = null;
            onProgress = false;
            onChooser = true;
            SetHeader("", "","Ricoh   ·   Canon   ·   colas de servidor");

            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, BackColor = Theme.Paper, Margin = Padding.Empty };
            for (int i = 0; i < 3; i++) grid.RowStyles.Add(new RowStyle(SizeType.Percent, 33.3f));

            var scan = new Card("01 — ESCÁNER", "Escanear e instalar",
                "Directorio de oficinas y rango /24: ICMP, TCP 9100 / 631 / 515, SNMP. Instalación con el driver detectado.")
            { Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, S(16)) };
            scan.Click += (s, e) => ShowScanner();

            var ricoh = new Card("02 — RICOH", "Ricoh · " + RicohModels.Names,
                "Modelo por SNMP / IPP. Driver PCL 6 del modelo o universal. Recrea colas existentes, elimina drivers sin uso, activa bandeja bypass.")
            { Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, S(16)) };
            var canon = new Card("03 — CANON", "Canon · todas las multifunción",
                "Generic Plus PCL6 por IP: driver instalado o del paquete, puerto TCP/IP con SNMP.")
            { Dock = DockStyle.Fill, Margin = new Padding(0) };
            ricoh.Click += (s, e) => { returnToScanner = false; ShowRicoh(); };
            canon.Click += (s, e) => { returnToScanner = false; ShowCanon(); };
            grid.Controls.Add(scan, 0, 0);
            grid.Controls.Add(ricoh, 0, 1);
            grid.Controls.Add(canon, 0, 2);

            body.Controls.Add(grid);
            body.Controls.Add(Footer($"Teclas  1 escáner · 2 Ricoh · 3 Canon · Esc salir      v{version}  ·  registro: {logPath}"));
        }

        // ================= 02: opciones Ricoh =================
        void ShowRicoh()
        {
            body.Controls.Clear();
            onChooser = false;
            printerRows.Clear();
            SetHeader("Ricoh", "Configuración", "Colas marcadas: se eliminan y se recrean con el mismo nombre y puerto.");

            // lista de impresoras instaladas
            // alto ajustado a las filas reales (max. 4 visibles, el resto con scroll): sin huecos vacios
            int visibles = Math.Max(1, Math.Min(4, GetPrinters().Count));
            var list = new Panel { Dock = DockStyle.Top, Height = S(32 + visibles * 40), AutoScroll = true, BackColor = Theme.Paper };
            var rows = new List<Control>();
            var head = new CheckRow { Header = true, StateColumn = true, Columns = new[] { "Impresora", "Driver actual", "Puerto / IP" }, Widths = new[] { .36f, .38f, .26f }, Dock = DockStyle.Top, Height = S(32) };
            foreach (var p in GetPrinters())
            {
                var row = new CheckRow
                {
                    Columns = new[] { p.Name, p.Driver, p.Host ?? p.Port }, Widths = head.Widths, Tag = p, Dock = DockStyle.Top, Height = S(40), StateColumn = true,
                    Checked = p.Name.IndexOf("ricoh", StringComparison.OrdinalIgnoreCase) >= 0 || p.Driver.IndexOf("ricoh", StringComparison.OrdinalIgnoreCase) >= 0,
                };
                printerRows.Add(row);
                rows.Add(row);
            }
            CheckInstalled(printerRows);
            if (printerRows.Count == 0)
                rows.Add(new Label { Text = "Sin colas de red en este equipo.", ForeColor = Theme.Muted, Dock = DockStyle.Top, Height = S(40), TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(S(14), 0, 0, 0) });
            for (int i = rows.Count - 1; i >= 0; i--) list.Controls.Add(rows[i]);
            list.Controls.Add(head);

            // nueva por IP
            chkNew = new CheckRow { Columns = new[] { "Agregar una Ricoh nueva por IP  ·  modelo autodetectado" }, Dock = DockStyle.Top, Height = S(40), Checked = printerRows.Count == 0 };
            var fields = new TableLayoutPanel { Dock = DockStyle.Top, Height = S(68), ColumnCount = 4, BackColor = Theme.Paper, Padding = new Padding(S(42), S(12), 0, 0) };
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
            lblProbe = new Label { Dock = DockStyle.Top, Height = S(26), Font = Theme.Sans(9f), ForeColor = Theme.Muted, Padding = new Padding(S(42), S(6), 0, 0) };

            EventHandler toggle = (s, e) => { fIp.Box.Enabled = fName.Box.Enabled = btnProbe.Enabled = chkNew.Checked; if (!chkNew.Checked) SetProbe("", Theme.Muted); };
            chkNew.CheckedChanged += toggle;
            toggle(null, null);
            fIp.Box.TextChanged += (s, e) => SetProbe("", Theme.Muted);
            btnProbe.Click += async (s, e) => await ProbeNewIp(interactive: false);

            btnInstall = new FlatBtn("Instalar", primary: true);
            var btnBack = new FlatBtn("Atrás", primary: false);
            btnInstall.Click += async (s, e) => await StartRicoh();
            btnBack.Click += (s, e) => ShowChooser();

            // Dock=Top apila en orden inverso: el ultimo anadido queda arriba
            body.Controls.Add(lblProbe);
            body.Controls.Add(fields);
            body.Controls.Add(chkNew);
            body.Controls.Add(Section("Nueva impresora"));
            body.Controls.Add(Gap(BlockGap));
            body.Controls.Add(list);
            body.Controls.Add(Section("Impresoras en este equipo"));
            body.Controls.Add(ButtonBar(btnInstall, btnBack));
        }

        /// <summary>
        /// Verde / rojo en las colas ya instaladas: la IP de su puerto responde como impresora o no.
        /// En paralelo y sin bloquear la pantalla; las colas sin IP (USB, WSD) quedan con el indicador apagado.
        /// </summary>
        static async void CheckInstalled(List<CheckRow> rows)
        {
            await Task.WhenAll(rows.Where(r => ((PrinterInfo)r.Tag).Host != null).Select(async r =>
            {
                r.State = ScanState.Checking;
                try { r.State = (await NetworkScan.Check(((PrinterInfo)r.Tag).Host, quick: false, System.Threading.CancellationToken.None)).State; }
                catch { r.State = ScanState.Unreachable; }
            }));
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
                if (interactive) Warn("IP no válida. Formato: 192.168.1.50");
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
                    if (interactive) Warn(r.Message + "\n\nSin cambios.");
                    return null;
            }
        }

        void SetProbe(string text, Color c) { lblProbe.Text = text; lblProbe.ForeColor = c; }
        void Warn(string text) => ThemedDialog.Info(scanner != null && scanner.Visible ? (IWin32Window)scanner : this, "Aviso", "Revisar", text);
        bool Ask(string text) => ThemedDialog.Confirm(this, "Ricoh", "¿Continuar?", text, "Continuar");

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
                    Warn($"Ya existe la cola «{newName}». Cambie el nombre o márquela para reinstalarla.");
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
                Warn("Ninguna cola marcada ni IP nueva.");
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
            if (offline.Count > 0 && !Ask("Sin respuesta o no Ricoh:\n\n" + string.Join("\n", offline) + "\n\nSe reinstalan igualmente con el driver Ricoh."))
                return;

            var confirm = new StringBuilder();
            foreach (var j in jobs.Where(j => !j.IsNew))
            {
                var p = selected.First(x => x.Name == j.Name);
                confirm.AppendLine($"· Reinstalar \"{j.Name}\" ({p.Host ?? p.Port}) con {j.Model.DriverName}");
            }
            foreach (var j in jobs.Where(j => j.IsNew)) confirm.AppendLine($"· Agregar \"{j.Name}\" en {j.Ip} con {j.Model.DriverName}");
            confirm.AppendLine("· Drivers Ricoh sin uso: se eliminan");
            if (!ThemedDialog.Confirm(this, "Ricoh", "Confirmar instalación", confirm.ToString().TrimEnd())) return;

            ShowProgress("Ricoh", "Instalando", "No cerrar hasta finalizar.");
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
            onProgress = true;
            onChooser = false;
            lblClose.Visible = false;

            var top = new Panel { Dock = DockStyle.Top, Height = S(34), BackColor = Theme.Paper };
            lblStep = new Label { Dock = DockStyle.Fill, Font = Theme.Title(12.5f), ForeColor = Theme.Black, Text = "Preparando…", TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true };
            lblPct = new Label { Dock = DockStyle.Right, Width = S(70), Font = Theme.Title(12.5f), ForeColor = Theme.GoldDeep, Text = "000%", TextAlign = ContentAlignment.MiddleRight };
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

            // al terminar se vuelve al inicio (o al escaner): la app sigue abierta; para salir, la X
            btnClose = new FlatBtn("Volver", primary: true) { Enabled = false };
            var btnLog = new FlatBtn("Ver registro", primary: false);
            btnClose.Click += (s, e) => Back();
            btnLog.Click += (s, e) => { if (File.Exists(logPath)) Process.Start("notepad.exe", logPath); };

            body.Controls.Add(logFrame);
            body.Controls.Add(Section("Registro"));
            body.Controls.Add(Gap(BlockGap));
            body.Controls.Add(progress);
            body.Controls.Add(Gap(SectionGap));
            body.Controls.Add(top);
            var spacer = Gap(BlockGap - 8); spacer.Dock = DockStyle.Bottom;
            body.Controls.Add(spacer);
            body.Controls.Add(ButtonBar(btnClose, btnLog));
        }

        /// <summary>Del resumen de una instalacion al inicio; si se lanzo desde el escaner, se reabre.</summary>
        void Back()
        {
            if (!closeAllowed) return;
            ShowChooser();
            if (returnToScanner) { returnToScanner = false; ShowScanner(); }
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
                case "STEP": tag = "▌ ";      tagColor = Theme.Gold; c = Theme.Paper; break;
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
            SetHeader(hTag, ok ? "Completado" : "Revisión necesaria", ok ? "Volver: Esc · Salir: ✕" : "Detalle en el registro.");
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
                p.ErrorDataReceived += (s, e) => { foreach (var err in StdErrLines(e.Data)) Log("ERR", err); };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                p.WaitForExit();
                return p.ExitCode;
            }
        }

        /// <summary>
        /// Errores reales de la salida de error de PowerShell. Con la salida redirigida, PowerShell manda
        /// progreso y errores serializados en CLIXML ("#&lt; CLIXML" + &lt;Objs&gt;): el progreso se descarta y de
        /// los errores se saca solo el texto.
        /// </summary>
        static IEnumerable<string> StdErrLines(string data)
        {
            if (string.IsNullOrWhiteSpace(data) || data.StartsWith("#< CLIXML")) yield break;
            if (!data.StartsWith("<Objs")) { yield return data; yield break; }
            foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(data, "<S S=\"Error\">(.*?)</S>"))
            {
                var text = WebUtility.HtmlDecode(m.Groups[1].Value).Replace("_x000D_", "").Replace("_x000A_", " ").Trim();
                if (text.Length > 0) yield return text;
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

        // ================= cola compartida en servidor =================
        /// <summary>Conecta \\servidor\cola: Add-Printer para el usuario actual y printui /ga para todos los usuarios.</summary>
        async Task RunShared(string unc)
        {
            ShowProgress("Servidor", "Conectando impresora", unc);
            var q = unc.Replace("'", "''");
            var script = string.Join("\n",
                "$ErrorActionPreference = 'Stop'",
                "$ProgressPreference = 'SilentlyContinue'",
                $"$c = '{q}'",
                "Write-Output 'STEP|15|Comprobando conexiones existentes'",
                "if (Get-Printer -Name $c -ErrorAction SilentlyContinue) { Remove-Printer -Name $c; Write-Output \"OK|Conexion anterior eliminada: $c\" }",
                "Write-Output 'STEP|40|Conectando y descargando el driver del servidor'",
                "Add-Printer -ConnectionName $c",
                "Write-Output \"OK|Conectada para este usuario: $c\"",
                "Write-Output 'STEP|80|Conexion para todos los usuarios del equipo'",
                "$p = Start-Process rundll32.exe -ArgumentList \"printui.dll,PrintUIEntry /ga /n`\"$c`\"\" -Wait -PassThru",
                "if ($p.ExitCode -eq 0) { Write-Output 'OK|Conexion global registrada (resto de usuarios al iniciar sesion)' } else { Write-Output \"WARN|printui /ga devolvio $($p.ExitCode)\" }",
                "Write-Output \"SUMMARY|Conectada $c\"",
                "Write-Output 'STEP|100|Finalizado'");
            var b64 = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
            int exit = await Task.Run(() => RunEngine($"-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {b64}"));
            Finish(exit == 0, exit == 0 ? "La impresora aparece como \"" + unc.TrimStart('\\').Split('\\').Last() + " en " + unc.TrimStart('\\').Split('\\')[0] + "\"." : null);
        }

        // ================= Canon =================
        const string CanonDriver = "Canon Generic Plus PCL6";

        static bool CanonDriverInstalled()
        {
            try
            {
                using (var q = new ManagementObjectSearcher("SELECT Name FROM Win32_PrinterDriver"))
                    return q.Get().Cast<ManagementObject>().Any(m => ((m["Name"] as string) ?? "").StartsWith(CanonDriver + ",", StringComparison.OrdinalIgnoreCase));
            }
            catch { return false; }
        }

        /// <summary>
        /// Canon por IP sin el asistente: el asistente se niega si ya hay una version posterior del driver
        /// ("Ya está instalada una versión posterior del controlador"). Aqui se usa la instalada, sea cual sea.
        /// </summary>
        void ShowCanon()
        {
            body.Controls.Clear();
            onChooser = false;
            AcceptButton = null;
            bool has = CanonDriverInstalled();
            SetHeader("Canon", "Nueva impresora", has
                ? "Driver Generic Plus PCL6 instalado · puerto TCP/IP + cola."
                : "Driver Generic Plus PCL6 del paquete · puerto TCP/IP + cola.");

            var fields = new TableLayoutPanel { Dock = DockStyle.Top, Height = S(68), ColumnCount = 3, RowCount = 1, BackColor = Theme.Paper, Padding = new Padding(0, S(8), 0, 0) };
            fields.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, S(200)));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, S(24)));
            fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            var ip = new LineField("Dirección IP", mono: true) { Dock = DockStyle.Fill, Margin = Padding.Empty };
            var name = new LineField("Nombre de la cola", mono: false) { Dock = DockStyle.Fill, Margin = Padding.Empty };
            name.Box.Text = "Canon";
            fields.Controls.Add(ip, 0, 0);
            fields.Controls.Add(new Panel { BackColor = Theme.Paper }, 1, 0);
            fields.Controls.Add(name, 2, 0);

            var help = new Label
            {
                Dock = DockStyle.Top, Height = S(64), Font = Theme.Sans(9f), ForeColor = Theme.Muted, Padding = new Padding(0, S(14), 0, 0),
                Text = "Puerto TCP/IP estándar con SNMP (public) y cola con Canon Generic Plus PCL6. IP con cola existente: se actualiza su driver.\n" +
                       "Asistente Canon: instalador oficial; rechaza instalar si hay una versión posterior del driver.",
            };

            var btnGo = new FlatBtn("Instalar", primary: true);
            var btnWizard = new FlatBtn("Asistente Canon", primary: false);
            var btnBack = new FlatBtn("Atrás", primary: false);
            async void Go()
            {
                var addr = ip.Box.Text.Trim();
                var queue = name.Box.Text.Trim().Length > 0 ? name.Box.Text.Trim() : "Canon";
                if (!IPAddress.TryParse(addr, out var a) || a.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork || addr.Count(c => c == '.') != 3)
                {
                    Warn("IP no válida. Formato: 192.168.1.50");
                    ip.Box.Focus();
                    return;
                }
                if (!ThemedDialog.Confirm(this, "Canon", queue, $"· Cola «{queue}» en {addr}\n· {CanonDriver} ({(has ? "ya instalado" : "del paquete")})")) return;
                await RunCanonDirect(addr, queue);
            }
            btnGo.Click += (s, e) => Go();
            btnWizard.Click += async (s, e) => await RunCanon();
            btnBack.Click += (s, e) => ShowChooser();
            ip.Box.KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Go(); } };
            name.Box.KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Go(); } };

            body.Controls.Add(help);
            body.Controls.Add(fields);
            body.Controls.Add(Section("Impresora Canon por IP"));
            body.Controls.Add(ButtonBar(btnGo, btnWizard, btnBack));
            ip.Box.Focus();
        }

        /// <summary>Driver Generic Plus PCL6 (el instalado o el del paquete), puerto TCP/IP con SNMP y cola.</summary>
        async Task RunCanonDirect(string ip, string name)
        {
            ShowProgress("Canon", "Instalando", $"{name}  ·  {ip}");
            int exit = -1;
            try
            {
                string inf = "";
                if (!await Task.Run(() => CanonDriverInstalled()))
                {
                    SetStep(10, "Preparando driver Canon del paquete");
                    var dir = await Task.Run(() => ExtractPayload("canon.zip", "canon"));
                    inf = Path.Combine(dir, "Driver", "CNP60MA64.INF");
                }
                string q(string v) => v.Replace("'", "''");
                var script = string.Join("\n",
                    "$ErrorActionPreference = 'Stop'",
                    "$ProgressPreference = 'SilentlyContinue'",
                    $"$drv = '{CanonDriver}'; $ip = '{q(ip)}'; $name = '{q(name)}'; $inf = '{q(inf)}'",
                    "Write-Output 'STEP|25|Driver Canon Generic Plus PCL6'",
                    "$d = Get-PrinterDriver -Name $drv -ErrorAction SilentlyContinue | Select-Object -First 1",
                    "if ($d) { $v = [uint64]$d.DriverVersion; $ver = '{0}.{1}.{2}.{3}' -f (($v -shr 48) -band 0xFFFF), (($v -shr 32) -band 0xFFFF), (($v -shr 16) -band 0xFFFF), ($v -band 0xFFFF); Write-Output \"OK|Driver ya instalado (v$ver): se usa ese, sin asistente\" }",
                    "else { pnputil.exe /add-driver \"$inf\" /install | Out-Null; Add-PrinterDriver -Name $drv; Write-Output 'OK|Driver instalado desde el paquete' }",
                    "Write-Output 'STEP|55|Puerto TCP/IP'",
                    "if (Get-PrinterPort -Name $ip -ErrorAction SilentlyContinue) { Write-Output \"OK|Puerto $ip ya existe\" } else { Add-PrinterPort -Name $ip -PrinterHostAddress $ip -SNMP 1 -SNMPCommunity public; Write-Output \"OK|Puerto $ip creado (SNMP activo)\" }",
                    "Write-Output 'STEP|80|Cola de impresión'",
                    "$old = Get-Printer | Where-Object PortName -eq $ip | Select-Object -First 1",
                    "if ($old) { Set-Printer -Name $old.Name -DriverName $drv; $name = $old.Name; Write-Output \"OK|Cola existente actualizada: $name\" }",
                    "else { if (Get-Printer -Name $name -ErrorAction SilentlyContinue) { $name = \"$name ($ip)\" }; Add-Printer -Name $name -DriverName $drv -PortName $ip; Write-Output \"OK|Cola creada: $name\" }",
                    "Write-Output \"SUMMARY|$name en $ip con $drv\"",
                    "Write-Output 'STEP|100|Finalizado'");
                var b64 = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
                exit = await Task.Run(() => RunEngine($"-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {b64}"));
            }
            catch (Exception ex)
            {
                Log("ERR", ex.Message);
            }
            Finish(exit == 0, exit == 0 ? "Bandejas y color: Preferencias de impresión de la cola." : null);
        }

        async Task RunCanon()
        {
            ShowProgress("Canon", "Generic Plus PCL6", "Siga los pasos del asistente de Canon.");
            bool ok = false;
            int code = -1;
            try
            {
                SetStep(10, "Preparando archivos del driver Canon");
                var dir = await Task.Run(() => ExtractPayload("canon.zip", "canon"));
                SetStep(40, "Asistente de Canon en curso");
                // el asistente es un proceso aparte: cerrarlo (termine o no) nunca cierra PrintDeploy
                code = await Task.Run(() =>
                {
                    using (var p = Process.Start(new ProcessStartInfo(Path.Combine(dir, "Setup.exe")) { WorkingDirectory = dir, UseShellExecute = true }))
                    {
                        p?.WaitForExit();
                        int exit = p?.ExitCode ?? 0;
                        WaitForProcessesIn(dir);   // Setup.exe puede delegar en otro instalador y salir antes
                        return exit;
                    }
                });
                ok = true;
                if (code == 0) Log("OK", "Asistente de Canon finalizado.");
                else Log("WARN", $"Asistente de Canon cerrado sin completar (código {code}).");
                SetStep(100, "Finalizado");
            }
            catch (Exception ex)
            {
                Log("ERR", ex.Message);
            }
            Finish(ok, !ok ? null : code == 0
                ? "«Versión posterior ya instalada»: usar Instalar en 03 Canon (sin asistente)."
                : "Asistente cerrado antes de terminar.");
        }

        /// <summary>Espera a que no quede ningun proceso ejecutandose desde esa carpeta (instaladores encadenados).</summary>
        static void WaitForProcessesIn(string dir)
        {
            var prefix = dir.TrimEnd('\\') + "\\";
            for (int i = 0; i < 3600; i++)   // tope: 1 hora
            {
                bool running;
                try
                {
                    using (var q = new ManagementObjectSearcher("SELECT ExecutablePath FROM Win32_Process"))
                        running = q.Get().Cast<ManagementObject>().Any(m => ((m["ExecutablePath"] as string) ?? "").StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
                }
                catch { return; }
                if (!running) return;
                System.Threading.Thread.Sleep(1000);
            }
        }
    }
}

