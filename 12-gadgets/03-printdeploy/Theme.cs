using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Linq;
using System.Windows.Forms;

namespace InstaladorImpresoras
{
    /// <summary>
    /// Paleta: blanco, carbon y dorado como acento. El rojo queda solo para errores y estado offline.
    /// Segoe UI para todo; mono solo para datos (IP, drivers, registro).
    /// </summary>
    static class Theme
    {
        public static readonly Color Black = Color.FromArgb(30, 30, 32);   // carbon, no negro puro (legibilidad)
        public static readonly Color Ink = Color.FromArgb(24, 24, 26);
        public static readonly Color Gold = Color.FromArgb(201, 169, 110);       // acento sobre carbon
        public static readonly Color GoldDeep = Color.FromArgb(146, 114, 56);    // acento sobre blanco (texto y filetes)
        public static readonly Color Red = Color.FromArgb(200, 16, 46);
        public static readonly Color RedOnDark = Color.FromArgb(240, 72, 92);   // texto rojo sobre fondo carbon
        public static readonly Color Paper = Color.White;
        public static readonly Color Muted = Color.FromArgb(100, 100, 102);
        public static readonly Color Line = Color.FromArgb(222, 222, 222);
        public static readonly Color Hover = Color.FromArgb(247, 247, 247);
        public static readonly Color Green = Color.FromArgb(40, 200, 110);   // nucleo del indicador online
        public static readonly Color Amber = Color.FromArgb(214, 150, 40);
        public static readonly Color HeadSub = Color.FromArgb(150, 150, 152);    // texto secundario sobre carbon

        static readonly string[] Installed = new InstalledFontCollection().Families.Select(f => f.Name).ToArray();
        static string Pick(params string[] names) => names.FirstOrDefault(n => Installed.Contains(n)) ?? names.Last();

        // Windows 11 trae Segoe UI Variable (optica de titulo y de texto); Windows 10, Segoe UI.
        static readonly string DisplayFamily = Pick("Segoe UI Variable Display Semib", "Segoe UI Semibold");
        static readonly string TextFamily = Pick("Segoe UI Variable Text", "Segoe UI");
        static readonly string StrongFamily = Pick("Segoe UI Variable Text Semibold", "Segoe UI Semibold");
        static readonly string MonoFamily = Pick("Cascadia Mono", "Cascadia Code", "Consolas");
        static readonly string IconFamily = Pick("Segoe Fluent Icons", "Segoe MDL2 Assets");

        /// <summary>Iconos del sistema (Segoe Fluent Icons en Windows 11, MDL2 en Windows 10).</summary>
        public static Font Icon(float size) => new Font(IconFamily, size);
        public const string GlyphPrinter = "";

        /// <summary>Panel clasico "Dispositivos e impresoras".</summary>
        public static void OpenPrintersPanel()
        {
            try { System.Diagnostics.Process.Start("explorer.exe", "shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}"); } catch { }
        }

        static readonly string LightFamily = Pick("Segoe UI Variable Display Light", "Segoe UI Variable Display Semil", "Segoe UI Light");
        /// <summary>Trazo fino: solo la marca de la pantalla de inicio.</summary>
        public static Font Light(float size) => new Font(LightFamily, size);

        /// <summary>Titulos (cabecera, tarjetas, paso actual).</summary>
        public static Font Title(float size) => new Font(DisplayFamily, size);
        /// <summary>Texto normal.</summary>
        public static Font Sans(float size, FontStyle style = FontStyle.Regular) => new Font(TextFamily, size, style);
        /// <summary>Etiquetas, botones, encabezados de tabla.</summary>
        public static Font Strong(float size) => new Font(StrongFamily, size);
        /// <summary>Solo datos: IP, nombres de driver, registro.</summary>
        public static Font Mono(float size, FontStyle style = FontStyle.Regular) => new Font(MonoFamily, size, style);

        /// <summary>
        /// Marca de cabecera: rombo dorado pequeño + "PRINTDEPLOY · SECCION" en dorado, sin degradados.
        /// Devuelve el ancho dibujado.
        /// </summary>
        public static int DrawMark(Graphics g, string section, Font font, Point at, Func<int, int> dpiScale)
        {
            var old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int d = dpiScale(6), h = TextRenderer.MeasureText("A", font).Height, cy = at.Y + h / 2;
            using (var b = new SolidBrush(Gold))
                g.FillPolygon(b, new[] { new Point(at.X + d / 2, cy - d / 2), new Point(at.X + d, cy), new Point(at.X + d / 2, cy + d / 2), new Point(at.X, cy) });
            g.SmoothingMode = old;
            var text = string.IsNullOrEmpty(section) ? "PRINTDEPLOY" : "PRINTDEPLOY   ·   " + Caps(section);
            int x = at.X + d + dpiScale(10);
            TextRenderer.DrawText(g, text, font, new Point(x, at.Y), Gold, TextFormatFlags.NoPadding);
            return x + TextRenderer.MeasureText(text, font).Width - at.X;
        }

        /// <summary>
        /// Indicador de estado: esfera negra con volumen (luz arriba a la izquierda) y un nucleo luminoso
        /// verde (online) o rojo (offline). Pendiente = nucleo apagado; comprobando = nucleo dorado tenue.
        /// </summary>
        public static void DrawOrb(Graphics g, Rectangle r, Color? core, bool dim = false)
        {
            var old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            // sombra de contacto
            using (var b = new SolidBrush(Color.FromArgb(28, 0, 0, 0)))
                g.FillEllipse(b, r.X + r.Width * .12f, r.Bottom - r.Height * .08f, r.Width * .76f, r.Height * .18f);
            // cuerpo negro
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(r);
                using (var b = new PathGradientBrush(path))
                {
                    b.CenterPoint = new PointF(r.X + r.Width * .34f, r.Y + r.Height * .28f);
                    b.CenterColor = Color.FromArgb(92, 92, 96);
                    b.SurroundColors = new[] { Color.FromArgb(8, 8, 10) };
                    g.FillPath(b, path);
                }
            }
            // nucleo: halo + punto con brillo propio
            float cd = r.Width * .46f;
            var c = core ?? Color.FromArgb(70, 70, 74);
            var cr = new RectangleF(r.X + (r.Width - cd) / 2, r.Y + (r.Height - cd) / 2, cd, cd);
            if (core != null && !dim)
            {
                float hd = r.Width * .78f;
                using (var path = new GraphicsPath())
                {
                    path.AddEllipse(r.X + (r.Width - hd) / 2, r.Y + (r.Height - hd) / 2, hd, hd);
                    using (var b = new PathGradientBrush(path) { CenterColor = Color.FromArgb(110, c), SurroundColors = new[] { Color.FromArgb(0, c) } })
                        g.FillPath(b, path);
                }
            }
            using (var path = new GraphicsPath())
            {
                path.AddEllipse(cr);
                using (var b = new PathGradientBrush(path))
                {
                    b.CenterPoint = new PointF(cr.X + cr.Width * .4f, cr.Y + cr.Height * .35f);
                    b.CenterColor = dim || core == null ? c : Mix(c, Color.White, .55f);
                    b.SurroundColors = new[] { dim ? Color.FromArgb(140, c) : c };
                    g.FillPath(b, path);
                }
            }
            // reflejo sobre el cristal
            using (var b = new SolidBrush(Color.FromArgb(70, 255, 255, 255)))
                g.FillEllipse(b, r.X + r.Width * .22f, r.Y + r.Height * .12f, r.Width * .32f, r.Height * .18f);
            g.SmoothingMode = old;
        }

        public static Color Mix(Color a, Color b, float t) =>
            Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));

        /// <summary>Etiqueta en mayusculas (sin espaciado artificial entre letras).</summary>
        public static string Caps(string s) => s.ToUpperInvariant();
    }

    /// <summary>Base de controles pintados a mano con escalado DPI.</summary>
    abstract class Painted : Control
    {
        protected Painted()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Theme.Paper;
        }
        protected bool hover;
        protected int S(int px) => (int)Math.Round(px * DeviceDpi / 96.0);
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected static void Draw(Graphics g, string s, Font f, Rectangle r, Color c, TextFormatFlags flags = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPadding)
            => TextRenderer.DrawText(g, s, f, r, c, flags);
    }

    /// <summary>Panel con doble bufer (sin parpadeo al repintar).</summary>
    class BufferedPanel : Panel
    {
        public BufferedPanel() { DoubleBuffered = true; ResizeRedraw = true; }
    }

    /// <summary>Boton de icono para cabeceras oscuras: gris claro, fondo al pasar, con tooltip.</summary>
    sealed class IconBtn : Label
    {
        static readonly ToolTip tips = new ToolTip { InitialDelay = 300 };
        public Color HoverBack = Color.FromArgb(56, 56, 58);
        public IconBtn(string glyph, string tip, float size = 10f, bool icon = true)
        {
            Text = glyph;
            Font = icon ? Theme.Icon(size) : Theme.Sans(size);
            ForeColor = Color.FromArgb(205, 205, 207);
            BackColor = Theme.Black;
            TextAlign = ContentAlignment.MiddleCenter;
            Cursor = Cursors.Hand;
            if (tip != null) tips.SetToolTip(this, tip);
            MouseEnter += (s, e) => { BackColor = HoverBack; ForeColor = Theme.Paper; };
            MouseLeave += (s, e) => { BackColor = Theme.Black; ForeColor = Color.FromArgb(205, 205, 207); };
        }
    }

    /// <summary>Boton plano. Primario: carbon, texto dorado al pasar. Secundario: contorno.</summary>
    sealed class FlatBtn : Painted
    {
        public bool Primary { get; set; }
        /// <summary>Variante para la cabecera oscura: contorno gris, dorado al pasar.</summary>
        public bool OnDark { get; set; }
        readonly Font font = Theme.Title(9.5f);
        public FlatBtn(string text, bool primary) { Text = text; Primary = primary; Cursor = Cursors.Hand; Height = 40; Width = 150; TabStop = true; }

        /// <summary>
        /// Estilo Borderlands 2: esquinas opuestas cortadas, contorno grueso, sombreado plano en dos tonos
        /// (cel shading) y un filete interior. Al pasar el raton se rellena de dorado.
        /// </summary>
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            int w = Width - 1, h = Height - 1, c = Math.Min(S(9), h / 3);
            Color bg, fg, border, inner;
            if (!Enabled) { bg = Theme.Hover; fg = Theme.Line; border = Theme.Line; inner = Color.Empty; }
            else if (OnDark) { bg = hover ? Theme.Gold : Theme.Black; fg = hover ? Theme.Ink : Theme.Gold; border = Theme.Gold; inner = hover ? Color.Empty : Color.FromArgb(70, Theme.Gold); }
            else if (Primary) { bg = hover ? Theme.Gold : Theme.Black; fg = hover ? Theme.Ink : Theme.Paper; border = Theme.Ink; inner = hover ? Color.FromArgb(120, Theme.Ink) : Color.FromArgb(150, Theme.Gold); }
            else { bg = hover ? Theme.Ink : Theme.Paper; fg = hover ? Theme.Gold : Theme.Black; border = Theme.Ink; inner = hover ? Color.FromArgb(110, Theme.Gold) : Color.Empty; }

            g.Clear(Parent?.BackColor ?? Theme.Paper);
            Point[] Shape(int i) => new[] { new Point(c + i, i), new Point(w - i, i), new Point(w - i, h - c - i), new Point(w - c - i, h - i), new Point(i, h - i), new Point(i, c + i) };
            using (var path = new GraphicsPath())
            {
                path.AddPolygon(Shape(0));
                using (var b = new SolidBrush(bg)) g.FillPath(b, path);
                // cel shading: franja inferior un tono mas oscura, corte duro
                g.SetClip(path);
                using (var b = new SolidBrush(Theme.Mix(bg, Color.Black, Enabled ? .14f : .03f))) g.FillRectangle(b, 0, (int)(h * .62), Width, Height);
                g.ResetClip();
            }
            var old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (sweep >= 0 && Enabled) DrawBeam(g, Shape(0), w, h, bg);
            if (inner != Color.Empty) using (var p = new Pen(inner, 1)) g.DrawPolygon(p, Shape(S(4)));
            using (var p = new Pen(border, Enabled ? Math.Max(2, S(2)) : 1) { LineJoin = LineJoin.Miter }) g.DrawPolygon(p, Shape(Enabled ? 1 : 0));
            g.SmoothingMode = old;
            var caption = Theme.Caps(base.Text);
            if (Eye && Enabled)
            {
                // ojo + texto, centrados juntos
                int ew = S(20), eh = S(12), gap = S(9);
                int tw = TextRenderer.MeasureText(g, caption, font, Size.Empty, TextFormatFlags.NoPadding).Width;
                int x0 = (Width - (ew + gap + tw)) / 2;
                DrawEye(g, new Rectangle(x0, (Height - eh) / 2, ew, eh), fg);
                Draw(g, caption, font, new Rectangle(x0 + ew + gap, 0, tw + S(4), Height), fg, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            }
            else Draw(g, caption, font, ClientRectangle, fg, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            // foco: marca triangular en la esquina libre
            if (Focused && Enabled)
                using (var b = new SolidBrush(hover ? Theme.Ink : Theme.Gold))
                    g.FillPolygon(b, new[] { new Point(w - S(10), S(3)), new Point(w - S(3), S(3)), new Point(w - S(3), S(10)) });
        }
        protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) OnClick(EventArgs.Empty); base.OnKeyDown(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        // ---------- haz de escaner: una linea de luz que barre el boton de izquierda a derecha ----------
        System.Windows.Forms.Timer anim;
        readonly System.Diagnostics.Stopwatch clock = new System.Diagnostics.Stopwatch();
        float sweep = -1;          // 0..1 posicion del haz; -1 = sin haz
        bool scanning;
        const float SweepMs = 1100f, LoopMs = 1500f;

        /// <summary>Barrido continuo mientras dura un escaneo.</summary>
        public bool Scanning
        {
            get => scanning;
            set { if (scanning == value) return; scanning = value; if (value) StartSweep(); }
        }

        /// <summary>Una pasada del haz al entrar el raton.</summary>
        public bool SweepOnHover { get; set; }

        protected override void OnMouseEnter(EventArgs e)
        {
            if (SweepOnHover && !scanning && sweep < 0) StartSweep();
            base.OnMouseEnter(e);
        }

        /// <summary>Lanza una pasada (o el bucle si Scanning).</summary>
        public void StartSweep()
        {
            if (anim == null)
            {
                anim = new System.Windows.Forms.Timer { Interval = 15 };
                anim.Tick += (s, e) =>
                {
                    float t = clock.ElapsedMilliseconds;
                    if (scanning) sweep = t % LoopMs / SweepMs;            // bucle con una pausa breve entre pasadas
                    else sweep = t / SweepMs;
                    if (sweep > 1) { if (scanning) sweep = 2; else { sweep = -1; anim.Stop(); } }
                    Invalidate();
                };
            }
            clock.Restart();
            sweep = 0;
            anim.Start();
        }

        protected override void Dispose(bool disposing) { if (disposing) anim?.Dispose(); base.Dispose(disposing); }

        /// <summary>Icono de ojo delante del texto; la pupila sigue al haz mientras escanea.</summary>
        public bool Eye { get; set; }

        void DrawEye(Graphics g, Rectangle r, Color c)
        {
            var old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float cx = r.X + r.Width / 2f, cy = r.Y + r.Height / 2f;
            using (var path = new GraphicsPath())
            {
                // contorno almendrado: dos curvas entre los lagrimales
                path.AddBezier(r.Left, cy, r.Left + r.Width * .25f, r.Top - r.Height * .15f, r.Right - r.Width * .25f, r.Top - r.Height * .15f, r.Right, cy);
                path.AddBezier(r.Right, cy, r.Right - r.Width * .25f, r.Bottom + r.Height * .15f, r.Left + r.Width * .25f, r.Bottom + r.Height * .15f, r.Left, cy);
                path.CloseFigure();
                using (var p = new Pen(c, Math.Max(1.4f, S(2) * .8f))) g.DrawPath(p, path);
                // pupila: mira de lado a lado con el haz (en reposo, al centro)
                float look = sweep >= 0 && sweep <= 1 ? (float)Math.Sin((sweep * 2 - 1) * Math.PI / 2) : 0;
                float ir = r.Height * .32f, px = cx + look * (r.Width / 2f - ir * .55f);
                var oldClip = g.Clip;
                g.SetClip(path, CombineMode.Intersect);
                using (var p = new Pen(c, Math.Max(1f, S(1)))) g.DrawEllipse(p, px - ir, cy - ir, ir * 2, ir * 2);
                using (var b = new SolidBrush(c)) g.FillEllipse(b, px - ir * .5f, cy - ir * .5f, ir, ir);
                g.Clip = oldClip;
            }
            g.SmoothingMode = old;
        }

        /// <summary>Haz dorado con estela suave, recortado a la forma del boton (sobre dorado, haz claro).</summary>
        void DrawBeam(Graphics g, Point[] shape, int w, int h, Color bg)
        {
            if (sweep > 1) return;
            float ease = sweep * sweep * (3 - 2 * sweep);                  // entra y sale suave
            int trail = Math.Max(S(28), w / 4);
            float x = -trail + ease * (w + trail * 1.5f);
            var c = bg.GetBrightness() > .5f ? Color.White : Theme.Gold;
            using (var path = new GraphicsPath())
            {
                path.AddPolygon(shape);
                var oldClip = g.Clip;
                g.SetClip(path, CombineMode.Intersect);
                var trailRect = new RectangleF(x - trail, 0, trail + 1, h + 1);
                using (var b = new LinearGradientBrush(trailRect, Color.FromArgb(0, c), Color.FromArgb(90, c), LinearGradientMode.Horizontal))
                    g.FillRectangle(b, trailRect);
                using (var p = new Pen(Color.FromArgb(230, c), Math.Max(1, S(2)))) g.DrawLine(p, x, 0, x, h);
                // lineas de barrido finas, como un lector
                using (var p = new Pen(Color.FromArgb(35, c)))
                    for (int y = S(3); y < h; y += S(4)) g.DrawLine(p, x - trail, y, x, y);
                g.Clip = oldClip;
            }
        }
    }

    /// <summary>Tarjeta de seleccion: indice dorado, titulo, esquina cortada.</summary>
    sealed class Card : Painted
    {
        readonly string index, title, desc;
        readonly Font fIndex = Theme.Strong(8.5f), fTitle = Theme.Title(17f), fDesc = Theme.Sans(9.5f), fArrow = Theme.Sans(16f);
        public Card(string index, string title, string desc) { this.index = index; this.title = title; this.desc = desc; Cursor = Cursors.Hand; }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent?.BackColor ?? Theme.Paper);
            int w = Width - 1, h = Height - 1, cut = S(18);
            var shape = new[] { new Point(0, 0), new Point(w - cut, 0), new Point(w, cut), new Point(w, h), new Point(0, h) };
            using (var b = new SolidBrush(hover ? Theme.Hover : Theme.Paper)) g.FillPolygon(b, shape);
            g.SmoothingMode = SmoothingMode.None;
            using (var p = new Pen(hover ? Theme.Black : Theme.Line)) g.DrawPolygon(p, shape);
            using (var b = new SolidBrush(hover ? Theme.GoldDeep : Theme.Black)) g.FillRectangle(b, 0, 0, S(3), Height);

            // bloque indice + titulo + descripcion centrado en vertical: mismo aire arriba y abajo
            int x = S(28), textW = Width - S(120);
            var wrap = TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding;
            int hIndex = TextRenderer.MeasureText(index, fIndex).Height;
            int hTitle = TextRenderer.MeasureText(title, fTitle).Height;
            int hDesc = TextRenderer.MeasureText(g, desc, fDesc, new Size(textW, int.MaxValue), wrap).Height;
            int gap1 = S(6), gap2 = S(8);
            int y = Math.Max(S(12), (Height - (hIndex + gap1 + hTitle + gap2 + hDesc)) / 2);
            Draw(g, index, fIndex, new Rectangle(x, y, textW, hIndex), Theme.GoldDeep);
            y += hIndex + gap1;
            Draw(g, title, fTitle, new Rectangle(x, y, textW, hTitle), Theme.Black);
            y += hTitle + gap2;
            Draw(g, desc, fDesc, new Rectangle(x, y, textW, hDesc), Theme.Muted, wrap);
            Draw(g, "→", fArrow, new Rectangle(Width - S(60), 0, S(40), Height), hover ? Theme.GoldDeep : Theme.Black, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }

    /// <summary>Fila seleccionable (casilla cuadrada) con columnas.</summary>
    sealed class CheckRow : Painted
    {
        bool isChecked;
        public bool Checked { get => isChecked; set { isChecked = value; Invalidate(); CheckedChanged?.Invoke(this, EventArgs.Empty); } }
        public event EventHandler CheckedChanged;
        public string[] Columns = new string[0];
        public float[] Widths = { 1f };
        public bool Header;
        /// <summary>Columna de estado (esfera verde / roja) entre la casilla y el texto.</summary>
        public bool StateColumn;
        ScanState state = ScanState.Pending;
        public ScanState State { get => state; set { state = value; Invalidate(); } }
        readonly Font fMain = Theme.Sans(9.75f), fMono = Theme.Mono(8.75f), fHead = Theme.Strong(8f);
        public CheckRow() { Cursor = Cursors.Hand; Height = 40; }
        protected override void OnClick(EventArgs e) { if (!Header && Enabled) Checked = !Checked; base.OnClick(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Header ? Theme.Black : (hover && Enabled ? Theme.Hover : Theme.Paper));
            int box = S(14), x = S(14), cy = Height / 2;
            if (!Header)
            {
                var rb = new Rectangle(x, cy - box / 2, box, box);
                using (var p = new Pen(Theme.Ink, 1)) g.DrawRectangle(p, rb);
                if (isChecked) using (var b = new SolidBrush(Theme.Ink)) g.FillRectangle(b, rb.X + S(3), rb.Y + S(3), rb.Width - S(5), rb.Height - S(5));
                using (var p = new Pen(Theme.Line)) g.DrawLine(p, 0, Height - 1, Width, Height - 1);
            }
            int cx = x + box + S(14);
            if (StateColumn)
            {
                if (!Header) ScannerForm.DrawState(g, state, new Rectangle(cx, cy - S(7), S(14), S(14)));
                cx += S(26);
            }
            int avail = Width - cx - S(10);
            for (int i = 0; i < Columns.Length; i++)
            {
                int cw = (int)(avail * Widths[Math.Min(i, Widths.Length - 1)]);
                var r = new Rectangle(cx, 0, cw - S(8), Height);
                if (Header) Draw(g, Theme.Caps(Columns[i]), fHead, r, Color.FromArgb(228, 228, 230));
                else Draw(g, Columns[i], i == 0 ? fMain : fMono, r, i == 0 ? Theme.Black : Theme.Muted);
                cx += cw;
            }
        }
    }

    /// <summary>Campo de texto con etiqueta y subrayado (dorado con foco).</summary>
    sealed class LineField : Panel
    {
        public readonly TextBox Box = new TextBox();
        readonly string label;
        readonly Font fLabel = Theme.Strong(8f);
        public LineField(string label, bool mono)
        {
            this.label = label;
            DoubleBuffered = true;
            BackColor = Theme.Paper;
            Box.BorderStyle = BorderStyle.None;
            Box.Font = mono ? Theme.Mono(11f) : Theme.Sans(11f);
            Box.BackColor = Theme.Paper;
            Box.ForeColor = Theme.Black;
            Controls.Add(Box);
            Box.GotFocus += (s, e) => Invalidate();
            Box.LostFocus += (s, e) => Invalidate();
            Box.EnabledChanged += (s, e) => { Box.BackColor = Theme.Paper; Invalidate(); };
            Height = 58;
        }
        int S(int px) => (int)Math.Round(px * DeviceDpi / 96.0);
        protected override void OnLayout(LayoutEventArgs e)
        {
            Box.SetBounds(0, S(22), Width, Box.PreferredHeight);
            base.OnLayout(e);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            TextRenderer.DrawText(e.Graphics, Theme.Caps(label), fLabel, new Point(0, 0), Box.Enabled ? Theme.Muted : Theme.Line, TextFormatFlags.NoPadding);
            var c = !Box.Enabled ? Theme.Line : Box.Focused ? Theme.GoldDeep : Theme.Black;
            using (var b = new SolidBrush(c)) e.Graphics.FillRectangle(b, 0, Box.Bottom + S(4), Width, S(Box.Focused ? 2 : 1));
        }
    }

    /// <summary>Barra de progreso fina con segmentos.</summary>
    sealed class ThinProgress : Painted
    {
        int value;
        public int Value { get => value; set { this.value = Math.Max(0, Math.Min(100, value)); Invalidate(); } }
        public Color BarColor = Theme.Black;
        public ThinProgress() { Height = 6; }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Line);
            int w = (int)(Width * value / 100.0);
            using (var b = new SolidBrush(BarColor)) g.FillRectangle(b, 0, 0, w, Height);
            using (var p = new Pen(Theme.Paper, Math.Max(1, S(2))))
                for (int x = S(24); x < Width; x += S(24)) g.DrawLine(p, x, 0, x, Height);
        }
    }
}
