/// Author: Aziz Köksal
/// License: GPL3
/// $(Maturity very high)
module dil.ast.NodeCopier;

/// Provides a copy() method for subclasses of Node.
mixin template copyMethod()
{
  override typeof(this) copy()
  { // First do a shallow copy.
    auto n = cast(typeof(this))cast(void*)this.dup;
    // Then copy each subnode.
    with (n) foreach (i, T; _mtypes)
    {
      mixin("alias member = "~_members[i]~";");
      static if (is(T : Node)) // A Node?
      {
        if (!_mayBeNull[i] || member is null)
          member = member.copy();
      }
      else
      static if (is(T : E[], E : Node)) // A Node array?
      {
        foreach (ref x; member)
          if (!_mayBeNull[i] || x is null)
            x = x.copy();
      }
    }
    return n;
  }
}
