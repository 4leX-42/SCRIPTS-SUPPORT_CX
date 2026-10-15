using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Linq;
using System.Windows.Forms;

namespace InstaladorImpresoras
{
    /// <summary>Paleta del despacho: blanco, negro y rojo. Serif para titulos, mono para datos.</summary>
    static class Theme
    {
        public static readonly Color Black = Color.FromArgb(30, 30, 32);   // carbon, no negro puro (legibilidad)
        public static readonly Color Ink = Color.FromArgb(24, 24, 26);
        public static readonly Color Red = Color.FromArgb(200, 16, 46);
        public static readonly Color RedDark = Color.FromArgb(150, 10, 32);
        public static readonly Color RedOnDark = Color.FromArgb(240, 72, 92);   // texto rojo sobre fondo carbon
        public static readonly Color Paper = Color.White;
        public static readonly Color Muted = Color.FromArgb(100, 100, 102);
        public static readonly Color Line = Color.FromArgb(222, 222, 222);
        public static readonly Color Hover = Color.FromArgb(247, 247, 247);
        public static readonly Color Amber = Color.FromArgb(214, 150, 40);

        static readonly string MonoFamily = new InstalledFontCollection().Families
            .Select(f => f.Name).FirstOrDefault(n => n == "Cascadia Mono" || n == "Cascadia Code") ?? "Consolas";

        public static Font Serif(float size, FontStyle style = FontStyle.Regular) => new Font("Georgia", size, style);
        public static Font Mono(float size, FontStyle style = FontStyle.Regular) => new Font(MonoFamily, size, style);
        public static Font Sans(float size, FontStyle style = FontStyle.Regular) => new Font("Segoe UI", size, style);

        /// <summary>Texto con degradado horizontal (p.ej. rojo -> blanco) para que se lea sobre fondo oscuro.</summary>
        public static void DrawGradientText(Graphics g, string text, Font font, Point at, Color from, Color to)
        {
            var old = g.TextRenderingHint;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            var fmt = (StringFormat)StringFormat.GenericTypographic.Clone();
            fmt.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
            var size = g.MeasureString(text, font, PointF.Empty, fmt);
            var rect = new RectangleF(at, new SizeF(Math.Max(1, size.Width + 2), Math.Max(1, size.Height)));
            using (var brush = new LinearGradientBrush(rect, from, to, LinearGradientMode.Horizontal) { WrapMode = WrapMode.TileFlipX })
                g.DrawString(text, font, brush, at, fmt);
            g.TextRenderingHint = old;
        }

        /// <summary>Texto en mayusculas espaciado (estilo etiqueta tecnica).</summary>
        public static string Caps(string s) => string.Join(" ", s.ToUpperInvariant().ToCharArray()).Replace("   ", "  ");
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

    /// <summary>Boton plano. Primario: negro -> rojo al pasar. Secundario: contorno.</summary>
    sealed class FlatBtn : Painted
    {
        public bool Primary { get; set; }
        /// <summary>Variante para la cabecera oscura: contorno gris claro, rojo al pasar.</summary>
        public bool OnDark { get; set; }
        readonly Font font = Theme.Mono(9f, FontStyle.Bold);
        public FlatBtn(string text, bool primary) { Text = text; Primary = primary; Cursor = Cursors.Hand; Height = 40; Width = 150; TabStop = true; }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            var r = ClientRectangle;
            Color bg, fg, border;
            if (!Enabled) { bg = Theme.Hover; fg = Theme.Line; border = Theme.Line; }
            else if (OnDark) { bg = hover ? Theme.Red : Theme.Black; fg = Theme.Paper; border = hover ? Theme.Red : Color.FromArgb(110, 110, 112); }
            else if (Primary) { bg = hover ? Theme.Red : Theme.Black; fg = Theme.Paper; border = bg; }
            else { bg = hover ? Theme.Black : Theme.Paper; fg = hover ? Theme.Paper : Theme.Black; border = Theme.Black; }
            g.Clear(Parent?.BackColor ?? Theme.Paper);
            using (var b = new SolidBrush(bg)) g.FillRectangle(b, r);
            using (var p = new Pen(border)) g.DrawRectangle(p, 0, 0, r.Width - 1, r.Height - 1);
            Draw(g, Theme.Caps(base.Text), font, r, fg, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            if (Focused && Enabled) using (var p = new Pen(Theme.Red, 2)) g.DrawLine(p, S(10), r.Height - S(6), r.Width - S(10), r.Height - S(6));
        }
        protected override void OnKeyDown(KeyEventArgs e) { if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) OnClick(EventArgs.Empty); base.OnKeyDown(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
    }

    /// <summary>Tarjeta de seleccion: indice mono rojo, titulo serif, esquina cortada.</summary>
    sealed class Card : Painted
    {
        readonly string index, title, desc;
        readonly Font fIndex = Theme.Mono(8.5f, FontStyle.Bold), fTitle = Theme.Serif(17f), fDesc = Theme.Sans(9.5f), fArrow = Theme.Mono(16f);
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
            using (var b = new SolidBrush(hover ? Theme.Red : Theme.Black)) g.FillRectangle(b, 0, 0, S(4), Height);

            int x = S(28);
            Draw(g, index, fIndex, new Rectangle(x, S(18), S(200), S(18)), Theme.Red);
            Draw(g, title, fTitle, new Rectangle(x, S(40), Width - S(110), S(34)), Theme.Black);
            Draw(g, desc, fDesc, new Rectangle(x, S(78), Width - S(120), Height - S(86)), Theme.Muted, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding);
            Draw(g, "→", fArrow, new Rectangle(Width - S(60), 0, S(40), Height), hover ? Theme.Red : Theme.Black, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        }
    }

    /// <summary>Fila seleccionable (casilla cuadrada roja) con columnas.</summary>
    sealed class CheckRow : Painted
    {
        bool isChecked;
        public bool Checked { get => isChecked; set { isChecked = value; Invalidate(); CheckedChanged?.Invoke(this, EventArgs.Empty); } }
        public event EventHandler CheckedChanged;
        public string[] Columns = new string[0];
        public float[] Widths = { 1f };
        public bool Header;
        readonly Font fMain = Theme.Sans(9.75f), fMono = Theme.Mono(8.75f), fHead = Theme.Mono(7.5f, FontStyle.Bold);
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
                using (var p = new Pen(isChecked ? Theme.Red : Theme.Ink, 1)) g.DrawRectangle(p, rb);
                if (isChecked) using (var b = new SolidBrush(Theme.Red)) g.FillRectangle(b, rb.X + S(3), rb.Y + S(3), rb.Width - S(5), rb.Height - S(5));
                using (var p = new Pen(Theme.Line)) g.DrawLine(p, 0, Height - 1, Width, Height - 1);
            }
            int cx = x + box + S(14);
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

    /// <summary>Campo de texto con etiqueta mono y subrayado (rojo con foco).</summary>
    sealed class LineField : Panel
    {
        public readonly TextBox Box = new TextBox();
        readonly string label;
        readonly Font fLabel = Theme.Mono(7.5f, FontStyle.Bold);
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
            var c = !Box.Enabled ? Theme.Line : Box.Focused ? Theme.Red : Theme.Black;
            using (var b = new SolidBrush(c)) e.Graphics.FillRectangle(b, 0, Box.Bottom + S(4), Width, S(Box.Focused ? 2 : 1));
        }
    }

    /// <summary>Barra de progreso fina con segmentos.</summary>
    sealed class ThinProgress : Painted
    {
        int value;
        public int Value { get => value; set { this.value = Math.Max(0, Math.Min(100, value)); Invalidate(); } }
        public Color BarColor = Theme.Red;
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
