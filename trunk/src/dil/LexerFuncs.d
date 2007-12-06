/++
  Author: Aziz Köksal
  License: GPL3
+/
module dil.LexerFuncs;

const char[3] LS = \u2028; /// Line separator.
const char[3] PS = \u2029; /// Paragraph separator.
const dchar LSd = 0x2028;
const dchar PSd = 0x2029;
static assert(LS[0] == PS[0] && LS[1] == PS[1]);

const uint _Z_ = 26; /// Control+Z

/// Returns true if d is a Unicode line or paragraph separator.
bool isUnicodeNewlineChar(dchar d)
{
  return d == LSd || d == PSd;
}

/// Returns true if p points to a line or paragraph separator.
bool isUnicodeNewline(char* p)
{
  return *p == LS[0] && p[1] == LS[1] && (p[2] == LS[2] || p[2] == PS[2]);
}

/++
  Returns true if p points to the start of a Newline.
  Newline: \n | \r | \r\n | LS | PS
+/
bool isNewline(char* p)
{
  return *p == '\n' || *p == '\r' || isUnicodeNewline(p);
}

/++
  Returns true if p points to the first character of an EndOfLine.
  EndOfLine: Newline | 0 | _Z_
+/
bool isEndOfLine(char* p)
{
  return isNewline(p) || *p == 0 || *p == _Z_;
}

/++
  Scans a Newline and sets p one character past it.
  Returns '\n' if scanned or 0 otherwise.
+/
dchar scanNewline(ref char* p)
{
  switch (*p)
  {
  case '\r':
    if (p[1] == '\n')
      ++p;
  case '\n':
    ++p;
    return '\n';
  default:
    if (isUnicodeNewline(p))
    {
      ++p; ++p; ++p;
      return '\n';
    }
  }
  return 0;
}