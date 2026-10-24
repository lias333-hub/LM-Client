part of 'main.dart';

// ---------------------------------------------------------------------
// أساس التصميم الموحّد: مسافات، استدارات، ومكوّنات صغيرة تُستخدم في كل الشاشات.
// القاعدة: استدارة البطاقات 14، استدارة العناصر 10، مسافات من مضاعفات 4.
// ---------------------------------------------------------------------
class Sp {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

class Rd {
  static const double card = 14;
  static const double control = 10;
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const IconBadge(this.icon, {super.key, this.color, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(Rd.control)),
      child: Icon(icon, size: size * 0.5, color: color ?? p.accent),
    );
  }
}

/// صف تنقّل: أيقونة + عنوان + وصف قصير + سهم.
class NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const NavRow({super.key, required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
        child: Row(children: <Widget>[
          IconBadge(icon),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(title, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
                ),
            ]),
          ),
          Icon(Icons.chevron_right, color: p.muted, size: 22),
        ]),
      ),
    );
  }
}

/// بلاطة مربعة صغيرة (أيقونة فوق نص) للشبكات.
class NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const NavTile({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return InkWell(
      borderRadius: BorderRadius.circular(Rd.control),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: Sp.sm),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Rd.control),
          border: Border.all(color: p.border),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Icon(icon, size: 22, color: p.accent),
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 11.5)),
        ]),
      ),
    );
  }
}

/// صف قائمة بسيط (أيقونة + نص كبير) للقائمة الجانبية.
class NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const NavItem({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(children: <Widget>[
            Icon(icon, size: 22, color: p.accent),
            const SizedBox(width: 14),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 16))),
          ]),
        ),
      ),
    );
  }
}
