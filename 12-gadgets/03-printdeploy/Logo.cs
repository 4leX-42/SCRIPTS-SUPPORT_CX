using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace InstaladorImpresoras
{
    /// <summary>
    /// Logo de PrintDeploy: ojo dorado incandescente (almendra con filo dorado, iris de fuego con fibras y pupila
    /// rasgada) sobre una placa carbon con borde dorado. El mismo dibujo da el icono (.ico) y el emblema de la cabecera.
    /// </summary>
    static class Logo
    {
        static readonly Dictionary<(int, bool), Bitmap> cache = new Dictionary<(int, bool), Bitmap>();

        /// <summary>Logo de 'size' px; plate = con placa carbon (icono) o sin ella (sobre la cabecera oscura).</summary>
        public static Bitmap Get(int size, bool plate)
        {
            if (!cache.TryGetValue((size, plate), out var bmp)) cache[(size, plate)] = bmp = Render(size, plate);
            return bmp;
        }

        static Bitmap Render(int size, bool plate)
        {
            const int SS = 4;
            int n = size * SS;
            using (var big = new Bitmap(n, n, PixelFormat.Format32bppPArgb))
            {
                using (var g = Graphics.FromImage(big))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.ScaleTransform(n / 100f, n / 100f);
                    Paint(g, plate, size);
                }
                var small = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
                using (var g = Graphics.FromImage(small))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(big, new Rectangle(0, 0, size, size));
                }
                return small;
            }
        }

        /// <summary>Dibujo en una rejilla de 100 x 100.</summary>
        static void Paint(Graphics g, bool plate, int size)
        {
            bool tiny = size <= 24;   // a 16-24 px: menos detalle y trazos mas gruesos
            if (plate)
                using (var path = Rounded(new RectangleF(2, 2, 96, 96), 22))
                {
                    using (var b = new LinearGradientBrush(new PointF(0, 0), new PointF(0, 100), Color.FromArgb(40, 40, 44), Color.FromArgb(12, 12, 14)))
                        g.FillPath(b, path);
                    using (var p = new Pen(Color.FromArgb(150, Theme.Gold), tiny ? 4 : 2.2f)) g.DrawPath(p, path);
                }

            var c = new PointF(50, 52);
            // resplandor dorado detras del ojo
            using (var glow = new GraphicsPath())
            {
                glow.AddEllipse(c.X - 42, c.Y - 30, 84, 60);
                using (var b = new PathGradientBrush(glow) { CenterColor = Color.FromArgb(110, 255, 196, 90), SurroundColors = new[] { Color.FromArgb(0, 255, 160, 40) } })
                    g.FillPath(b, glow);
            }
            // almendra
            using (var eye = new GraphicsPath())
            {
                eye.AddBezier(8, c.Y, 28, c.Y - 36, 72, c.Y - 36, 92, c.Y);
                eye.AddBezier(92, c.Y, 72, c.Y + 36, 28, c.Y + 36, 8, c.Y);
                eye.CloseFigure();
                using (var b = new PathGradientBrush(eye) { CenterPoint = c, CenterColor = Color.FromArgb(60, 34, 8), SurroundColors = new[] { Color.FromArgb(14, 10, 6) } })
                    g.FillPath(b, eye);

                var clip = g.Clip;
                g.SetClip(eye, CombineMode.Intersect);
                // iris de fuego: blanco-amarillo en el centro, oro, cobre en el borde
                float ir = 22;
                using (var iris = new GraphicsPath())
                {
                    iris.AddEllipse(c.X - ir, c.Y - ir, ir * 2, ir * 2);
                    using (var b = new PathGradientBrush(iris) { CenterPoint = c })
                    {
                        b.InterpolationColors = new ColorBlend
                        {
                            Colors = new[] { Color.FromArgb(120, 44, 6), Color.FromArgb(206, 120, 24), Theme.Gold, Color.FromArgb(255, 222, 140), Color.FromArgb(255, 248, 220) },
                            Positions = new[] { 0f, .3f, .6f, .85f, 1f },
                        };
                        g.FillPath(b, iris);
                    }
                }
                // fibras
                if (!tiny)
                    using (var p1 = new Pen(Color.FromArgb(120, 120, 50, 8), .8f))
                    using (var p2 = new Pen(Color.FromArgb(130, 255, 236, 180), .6f))
                        for (int i = 0; i < 36; i++)
                        {
                            double a = i * Math.PI * 2 / 36;
                            float r0 = 6, r1 = ir * (.78f + .2f * (i * 7 % 5) / 4f);
                            g.DrawLine(i % 2 == 0 ? p1 : p2, c.X + (float)Math.Cos(a) * r0, c.Y + (float)Math.Sin(a) * r0, c.X + (float)Math.Cos(a) * r1, c.Y + (float)Math.Sin(a) * r1);
                        }
                using (var p = new Pen(Color.FromArgb(200, 70, 26, 4), tiny ? 2.4f : 1.6f)) g.DrawEllipse(p, c.X - ir, c.Y - ir, ir * 2, ir * 2);
                // pupila rasgada con filo incandescente
                float ph = 34, pw = tiny ? 6 : 4.6f;
                using (var pupil = new GraphicsPath())
                {
                    pupil.AddBezier(c.X, c.Y - ph / 2, c.X + pw, c.Y - ph * .2f, c.X + pw, c.Y + ph * .2f, c.X, c.Y + ph / 2);
                    pupil.AddBezier(c.X, c.Y + ph / 2, c.X - pw, c.Y + ph * .2f, c.X - pw, c.Y - ph * .2f, c.X, c.Y - ph / 2);
                    using (var p = new Pen(Color.FromArgb(220, 255, 236, 170), tiny ? 2.6f : 2)) g.DrawPath(p, pupil);
                    using (var b = new SolidBrush(Color.FromArgb(8, 6, 4))) g.FillPath(b, pupil);
                }
                // brillo humedo
                using (var b = new SolidBrush(Color.FromArgb(200, 255, 255, 255))) g.FillEllipse(b, c.X + 7, c.Y - 15, 7, 5);
                g.Clip = clip;
                clip.Dispose();
                // sombra del parpado superior
                using (var p = new Pen(Color.FromArgb(110, 0, 0, 0), 6)) g.DrawBezier(p, 10, c.Y, 29, c.Y - 33, 71, c.Y - 33, 90, c.Y);
                // filo dorado de la almendra (claro arriba, oscuro abajo)
                using (var b = new LinearGradientBrush(new PointF(0, c.Y - 30), new PointF(0, c.Y + 30), Color.FromArgb(255, 236, 186), Theme.GoldDeep))
                using (var p = new Pen(b, tiny ? 6 : 3.6f) { LineJoin = LineJoin.Miter, MiterLimit = 8 })
                    g.DrawPath(p, eye);
            }
        }

        static GraphicsPath Rounded(RectangleF r, float rad)
        {
            var p = new GraphicsPath();
            float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        /// <summary>Escribe un .ico con entradas PNG (16-256 px). Para regenerar app.ico.</summary>
        public static void SaveIco(string path)
        {
            var sizes = new[] { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
            var pngs = new List<byte[]>();
            foreach (var s in sizes)
                using (var ms = new MemoryStream()) { Render(s, true).Save(ms, ImageFormat.Png); pngs.Add(ms.ToArray()); }
            using (var f = new BinaryWriter(File.Create(path)))
            {
                f.Write((short)0); f.Write((short)1); f.Write((short)sizes.Length);
                int offset = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++)
                {
                    f.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i])); f.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                    f.Write((byte)0); f.Write((byte)0); f.Write((short)1); f.Write((short)32);
                    f.Write(pngs[i].Length); f.Write(offset);
                    offset += pngs[i].Length;
                }
                foreach (var p in pngs) f.Write(p);
            }
        }
    }
}
