/++
  Author: Aziz Köksal
  License: GPL3
+/
module dil.lexer.Lexer;

import dil.Token;
import dil.Information;
import dil.Keywords;
import dil.Identifier;
import dil.Messages;
import dil.HtmlEntities;
import dil.CompilerInfo;
import dil.IdTable;
import dil.Unicode;
import tango.stdc.stdlib : strtof, strtod, strtold;
import tango.stdc.errno : errno, ERANGE;
import tango.stdc.time : time_t, time, ctime;
import tango.stdc.string : strlen;
import common;

public import dil.lexer.Funcs;

/++
  The Lexer analyzes the characters of a source text and
  produces a doubly-linked list of tokens.
+/
class Lexer
{
  Token* head;      /// The head of the doubly linked token list.
  Token* tail;      /// The tail of the linked list. Set in scan().
  Token* token;     /// Points to the current token in the token list.
  string text;      /// The source text.
  char[] filePath;  /// Path to the source text.
  char* p;          /// Points to the current character in the source text.
  char* end;        /// Points one character past the end of the source text.

  // Members used for error messages:
  InfoManager infoMan;
  LexerError[] errors;
  /// Always points to the beginning of the current line.
  char* lineBegin;
//   Token* newline;     /// Current newline token.
  uint lineNum = 1;   /// Current, actual source text line number.
  uint lineNum_hline; /// Line number set by #line.
  uint inTokenString; /// > 0 if inside q{ }
  char[] errorPath;   /// The path displayed in error messages.

  /++
    Construct a Lexer object.
    Params:
      text     = the UTF-8 source code.
      filePath = the path to the source code; used for error messages.
  +/
  this(string text, string filePath, InfoManager infoMan = null)
  {
    this.filePath = this.errorPath = filePath;
    this.infoMan = infoMan;

    this.text = text;
    if (text.length == 0 || text[$-1] != 0)
    {
      this.text.length = this.text.length + 1;
      this.text[$-1] = 0;
    }

    this.p = this.text.ptr;
    this.end = this.p + this.text.length;
    this.lineBegin = this.p;

    this.head = new Token;
    this.head.type = TOK.HEAD;
    this.head.start = this.head.end = this.p;
    this.token = this.head;
    // Add a newline as the first token after the head.
    auto newline = new Token;
    newline.type = TOK.Newline;
    newline.setWhitespaceFlag();
    newline.start = newline.end = this.p;
    newline.filePath = this.errorPath;
    newline.lineNum = 1;
    newline.lineNum_hline = 0;
    // Link in.
    this.token.next = newline;
    newline.prev = this.token;
    this.token = newline;
//     this.newline = newline;
    scanShebang();
  }

  ~this()
  {
    auto token = head.next;
    while (token !is null)
    {
      assert(token.type == TOK.EOF ? token == tail && token.next is null : 1);
      delete token.prev;
      token = token.next;
    }
    delete tail;
  }

  /++
    The "shebang" may optionally appear once at the beginning of a file.
    Regexp: #![^\EndOfLine]*
  +/
  void scanShebang()
  {
    if (*p == '#' && p[1] == '!')
    {
      auto t = new Token;
      t.type = TOK.Shebang;
      t.setWhitespaceFlag();
      t.start = p;
      ++p;
      while (!isEndOfLine(++p))
        isascii(*p) || decodeUTF8();
      t.end = p;
      this.token.next = t;
      t.prev = this.token;
    }
  }

  void finalizeSpecialToken(ref Token t)
  {
    assert(t.srcText[0..2] == "__");
    switch (t.type)
    {
    case TOK.FILE:
      t.str = this.errorPath;
      break;
    case TOK.LINE:
      t.uint_ = this.errorLineNumber(this.lineNum);
      break;
    case TOK.DATE,
         TOK.TIME,
         TOK.TIMESTAMP:
      time_t time_val;
      time(&time_val);
      char* str = ctime(&time_val);
      char[] time_str = str[0 .. strlen(str)];
      switch (t.type)
      {
      case TOK.DATE:
        time_str = time_str[4..11] ~ time_str[20..24] ~ \0; break;
      case TOK.TIME:
        time_str = time_str[11..19] ~ \0; break;
      case TOK.TIMESTAMP:
        time_str = time_str[0..24] ~ \0; break;
      default: assert(0);
      }
      t.str = time_str;
      break;
    case TOK.VENDOR:
      t.str = VENDOR;
      break;
    case TOK.VERSION:
      t.uint_ = VERSION_MAJOR*1000 + VERSION_MINOR;
      break;
    default:
      assert(0);
    }
  }

  private void setLineBegin(char* p)
  {
    // Check that we can look behind one character.
    assert((p-1) >= text.ptr && p < end);
    // Check that previous character is a newline.
    assert(isNewlineEnd(p - 1));
    this.lineBegin = p;
  }

  private void scanNext(ref Token* t)
  {
    assert(t !is null);
    if (t.next)
    {
      t = t.next;
//       if (t.type == TOK.Newline)
//         this.newline = t;
    }
    else if (t != this.tail)
    {
      Token* new_t = new Token;
      scan(*new_t);
      new_t.prev = t;
      t.next = new_t;
      t = new_t;
    }
  }

  /// Advance t one token forward.
  void peek(ref Token* t)
  {
    scanNext(t);
  }

  /// Advance to the next token in the source text.
  TOK nextToken()
  {
    scanNext(this.token);
    return this.token.type;
  }

  /// Returns true if p points to the last character of a Newline.
  bool isNewlineEnd(char* p)
  {
    if (*p == '\n' || *p == '\r')
      return true;
    if (*p == LS[2] || *p == PS[2])
      if ((p-2) >= text.ptr)
        if (p[-1] == LS[1] && p[-2] == LS[0])
          return true;
    return false;
  }

  /++
    This is the old scan method.
    TODO: profile old and new to see which one is faster.
  +/
  public void scan(ref Token t)
  in
  {
    assert(text.ptr <= p && p < end);
  }
  out
  {
    assert(text.ptr <= t.start && t.start < end, Token.toString(t.type));
    assert(text.ptr <= t.end && t.end <= end, Token.toString(t.type));
  }
  body
  {
    // Scan whitespace.
    if (isspace(*p))
    {
      t.ws = p;
      while (isspace(*++p))
      {}
    }

    // Scan a token.
    uint c = *p;
    {
      t.start = p;
      // Newline.
      switch (*p)
      {
      case '\r':
        if (p[1] == '\n')
          ++p;
      case '\n':
        assert(isNewlineEnd(p));
        ++p;
        ++lineNum;
        setLineBegin(p);
//         this.newline = &t;
        t.type = TOK.Newline;
        t.setWhitespaceFlag();
        t.filePath = this.errorPath;
        t.lineNum = lineNum;
        t.lineNum_hline = lineNum_hline;
        t.end = p;
        return;
      default:
        if (isUnicodeNewline(p))
        {
          ++p; ++p;
          goto case '\n';
        }
      }
      // Identifier or string literal.
      if (isidbeg(c))
      {
        if (c == 'r' && p[1] == '"' && ++p)
          return scanRawStringLiteral(t);
        if (c == 'x' && p[1] == '"')
          return scanHexStringLiteral(t);
      version(D2)
      {
        if (c == 'q' && p[1] == '"')
          return scanDelimitedStringLiteral(t);
        if (c == 'q' && p[1] == '{')
          return scanTokenStringLiteral(t);
      }
        // Scan identifier.
      Lidentifier:
        do
        { c = *++p; }
        while (isident(c) || !isascii(c) && isUnicodeAlpha())

        t.end = p;

        auto id = IdTable.lookup(t.srcText);
        t.type = id.type;
        t.ident = id;

        if (t.type == TOK.Identifier || t.isKeyword)
          return;
        else if (t.isSpecialToken)
          finalizeSpecialToken(t);
        else if (t.type == TOK.EOF)
        {
          tail = &t;
          assert(t.srcText == "__EOF__");
        }
        else
          assert(0, "unexpected token type: " ~ Token.toString(t.type));
        return;
      }

      if (isdigit(c))
        return scanNumber(t);

      if (c == '/')
      {
        c = *++p;
        switch(c)
        {
        case '=':
          ++p;
          t.type = TOK.DivAssign;
          t.end = p;
          return;
        case '+':
          return scanNestedComment(t);
        case '*':
          return scanBlockComment(t);
        case '/':
          while (!isEndOfLine(++p))
            isascii(*p) || decodeUTF8();
          t.type = TOK.Comment;
          t.setWhitespaceFlag();
          t.end = p;
          return;
        default:
          t.type = TOK.Div;
          t.end = p;
          return;
        }
      }

      switch (c)
      {
      case '\'':
        return scanCharacterLiteral(t);
      case '`':
        return scanRawStringLiteral(t);
      case '"':
        return scanNormalStringLiteral(t);
      case '\\':
        char[] buffer;
        do
        {
          c = scanEscapeSequence();
          if (isascii(c))
            buffer ~= c;
          else
            encodeUTF8(buffer, c);
        } while (*p == '\\')
        buffer ~= 0;
        t.type = TOK.String;
        t.str = buffer;
        t.end = p;
        return;
      case '>': /* >  >=  >>  >>=  >>>  >>>= */
        c = *++p;
        switch (c)
        {
        case '=':
          t.type = TOK.GreaterEqual;
          goto Lcommon;
        case '>':
          if (p[1] == '>')
          {
            ++p;
            if (p[1] == '=')
            { ++p;
              t.type = TOK.URShiftAssign;
            }
            else
              t.type = TOK.URShift;
          }
          else if (p[1] == '=')
          {
            ++p;
            t.type = TOK.RShiftAssign;
          }
          else
            t.type = TOK.RShift;
          goto Lcommon;
        default:
          t.type = TOK.Greater;
          goto Lcommon2;
        }
        assert(0);
      case '<': /* <  <=  <>  <>=  <<  <<= */
        c = *++p;
        switch (c)
        {
        case '=':
          t.type = TOK.LessEqual;
          goto Lcommon;
        case '<':
          if (p[1] == '=') {
            ++p;
            t.type = TOK.LShiftAssign;
          }
          else
            t.type = TOK.LShift;
          goto Lcommon;
        case '>':
          if (p[1] == '=') {
            ++p;
            t.type = TOK.LorEorG;
          }
          else
            t.type = TOK.LorG;
          goto Lcommon;
        default:
          t.type = TOK.Less;
          goto Lcommon2;
        }
        assert(0);
      case '!': /* !  !<  !>  !<=  !>=  !<>  !<>= */
        c = *++p;
        switch (c)
        {
        case '<':
          c = *++p;
          if (c == '>')
          {
            if (p[1] == '=') {
              ++p;
              t.type = TOK.Unordered;
            }
            else
              t.type = TOK.UorE;
          }
          else if (c == '=')
          {
            t.type = TOK.UorG;
          }
          else {
            t.type = TOK.UorGorE;
            goto Lcommon2;
          }
          goto Lcommon;
        case '>':
          if (p[1] == '=')
          {
            ++p;
            t.type = TOK.UorL;
          }
          else
            t.type = TOK.UorLorE;
          goto Lcommon;
        case '=':
          t.type = TOK.NotEqual;
          goto Lcommon;
        default:
          t.type = TOK.Not;
          goto Lcommon2;
        }
        assert(0);
      case '.': /* .  .[0-9]  ..  ... */
        if (p[1] == '.')
        {
          ++p;
          if (p[1] == '.') {
            ++p;
            t.type = TOK.Ellipses;
          }
          else
            t.type = TOK.Slice;
        }
        else if (isdigit(p[1]))
        {
          return scanReal(t);
        }
        else
          t.type = TOK.Dot;
        goto Lcommon;
      case '|': /* |  ||  |= */
        c = *++p;
        if (c == '=')
          t.type = TOK.OrAssign;
        else if (c == '|')
          t.type = TOK.OrLogical;
        else {
          t.type = TOK.OrBinary;
          goto Lcommon2;
        }
        goto Lcommon;
      case '&': /* &  &&  &= */
        c = *++p;
        if (c == '=')
          t.type = TOK.AndAssign;
        else if (c == '&')
          t.type = TOK.AndLogical;
        else {
          t.type = TOK.AndBinary;
          goto Lcommon2;
        }
        goto Lcommon;
      case '+': /* +  ++  += */
        c = *++p;
        if (c == '=')
          t.type = TOK.PlusAssign;
        else if (c == '+')
          t.type = TOK.PlusPlus;
        else {
          t.type = TOK.Plus;
          goto Lcommon2;
        }
        goto Lcommon;
      case '-': /* -  --  -= */
        c = *++p;
        if (c == '=')
          t.type = TOK.MinusAssign;
        else if (c == '-')
          t.type = TOK.MinusMinus;
        else {
          t.type = TOK.Minus;
          goto Lcommon2;
        }
        goto Lcommon;
      case '=': /* =  == */
        if (p[1] == '=') {
          ++p;
          t.type = TOK.Equal;
        }
        else
          t.type = TOK.Assign;
        goto Lcommon;
      case '~': /* ~  ~= */
         if (p[1] == '=') {
           ++p;
           t.type = TOK.CatAssign;
         }
         else
           t.type = TOK.Tilde;
         goto Lcommon;
      case '*': /* *  *= */
         if (p[1] == '=') {
           ++p;
           t.type = TOK.MulAssign;
         }
         else
           t.type = TOK.Mul;
         goto Lcommon;
      case '^': /* ^  ^= */
         if (p[1] == '=') {
           ++p;
           t.type = TOK.XorAssign;
         }
         else
           t.type = TOK.Xor;
         goto Lcommon;
      case '%': /* %  %= */
         if (p[1] == '=') {
           ++p;
           t.type = TOK.ModAssign;
         }
         else
           t.type = TOK.Mod;
         goto Lcommon;
      // Single character tokens:
      case '(':
        t.type = TOK.LParen;
        goto Lcommon;
      case ')':
        t.type = TOK.RParen;
        goto Lcommon;
      case '[':
        t.type = TOK.LBracket;
        goto Lcommon;
      case ']':
        t.type = TOK.RBracket;
        goto Lcommon;
      case '{':
        t.type = TOK.LBrace;
        goto Lcommon;
      case '}':
        t.type = TOK.RBrace;
        goto Lcommon;
      case ':':
        t.type = TOK.Colon;
        goto Lcommon;
      case ';':
        t.type = TOK.Semicolon;
        goto Lcommon;
      case '?':
        t.type = TOK.Question;
        goto Lcommon;
      case ',':
        t.type = TOK.Comma;
        goto Lcommon;
      case '$':
        t.type = TOK.Dollar;
      Lcommon:
        ++p;
      Lcommon2:
        t.end = p;
        return;
      case '#':
        return scanSpecialTokenSequence(t);
      default:
      }

      // Check for EOF
      if (isEOF(c))
      {
        assert(isEOF(*p), ""~*p);
        t.type = TOK.EOF;
        t.end = p;
        tail = &t;
        assert(t.start == t.end);
        return;
      }

      if (!isascii(c))
      {
        c = decodeUTF8();
        if (isUniAlpha(c))
          goto Lidentifier;
      }

      error(t.start, MID.IllegalCharacter, cast(dchar)c);

      ++p;
      t.type = TOK.Illegal;
      t.setWhitespaceFlag();
      t.dchar_ = c;
      t.end = p;
      return;
    }
  }

  template toUint(char[] T)
  {
    static assert(0 < T.length && T.length <= 4);
    static if (T.length == 1)
      const uint toUint = T[0];
    else
      const uint toUint = (T[0] << ((T.length-1)*8)) | toUint!(T[1..$]);
  }
  static assert(toUint!("\xAA\xBB\xCC\xDD") == 0xAABBCCDD);

  // Can't use this yet due to a bug in DMD (bug id=1534).
  template case_(char[] str, TOK tok, char[] label)
  {
    const char[] case_ =
      `case `~toUint!(str).stringof~`:

         goto `~label~`;`;
  }

  template case_L4(char[] str, TOK tok)
  {
    const char[] case_L4 = case_!(str, tok, "Lcommon_4");
  }

  template case_L3(char[] str, TOK tok)
  {
    const char[] case_L3 = case_!(str, tok, "Lcommon_3");
  }

  template case_L2(char[] str, TOK tok)
  {
    const char[] case_L2 = case_!(str, tok, "Lcommon_2");
  }

  template case_L1(char[] str, TOK tok)
  {
    const char[] case_L3 = case_!(str, tok, "Lcommon");
  }

  public void scan_(ref Token t)
  in
  {
    assert(text.ptr <= p && p < end);
  }
  out
  {
    assert(text.ptr <= t.start && t.start < end, Token.toString(t.type));
    assert(text.ptr <= t.end && t.end <= end, Token.toString(t.type));
  }
  body
  {
    // Scan whitespace.
    if (isspace(*p))
    {
      t.ws = p;
      while (isspace(*++p))
      {}
    }

    // Scan a token.
    t.start = p;
    // Newline.
    switch (*p)
    {
    case '\r':
      if (p[1] == '\n')
        ++p;
    case '\n':
      assert(isNewlineEnd(p));
      ++p;
      ++lineNum;
      setLineBegin(p);
//       this.newline = &t;
      t.type = TOK.Newline;
      t.setWhitespaceFlag();
      t.filePath = this.errorPath;
      t.lineNum = lineNum;
      t.lineNum_hline = lineNum_hline;
      t.end = p;
      return;
    default:
      if (isUnicodeNewline(p))
      {
        ++p; ++p;
        goto case '\n';
      }
    }

    uint c = *p;
    assert(end - p != 0);
    switch (end - p)
    {
    case 1:
      goto L1character;
    case 2:
      c <<= 8; c |= p[1];
      goto L2characters;
    case 3:
      c <<= 8; c |= p[1]; c <<= 8; c |= p[2];
      goto L3characters;
    default:
      version(BigEndian)
        c = *cast(uint*)p;
      else
      {
        c <<= 8; c |= p[1]; c <<= 8; c |= p[2]; c <<= 8; c |= p[3];
        /+
        c = *cast(uint*)p;
        asm
        {
          mov EDX, c;
          bswap EDX;
          mov c, EDX;
        }
        +/
      }
    }

    // 4 character tokens.
    switch (c)
    {
    case toUint!(">>>="):
      t.type = TOK.RShiftAssign;
      goto Lcommon_4;
    case toUint!("!<>="):
      t.type = TOK.Unordered;
    Lcommon_4:
      p += 4;
      t.end = p;
      return;
    default:
    }

    c >>>= 8;
  L3characters:
    assert(p == t.start);
    // 3 character tokens.
    switch (c)
    {
    case toUint!(">>="):
      t.type = TOK.RShiftAssign;
      goto Lcommon_3;
    case toUint!(">>>"):
      t.type = TOK.URShift;
      goto Lcommon_3;
    case toUint!("<>="):
      t.type = TOK.LorEorG;
      goto Lcommon_3;
    case toUint!("<<="):
      t.type = TOK.LShiftAssign;
      goto Lcommon_3;
    case toUint!("!<="):
      t.type = TOK.UorG;
      goto Lcommon_3;
    case toUint!("!>="):
      t.type = TOK.UorL;
      goto Lcommon_3;
    case toUint!("!<>"):
      t.type = TOK.UorE;
      goto Lcommon_3;
    case toUint!("..."):
      t.type = TOK.Ellipses;
    Lcommon_3:
      p += 3;
      t.end = p;
      return;
    default:
    }

    c >>>= 8;
  L2characters:
    assert(p == t.start);
    // 2 character tokens.
    switch (c)
    {
    case toUint!("/+"):
      ++p; // Skip /
      return scanNestedComment(t);
    case toUint!("/*"):
      ++p; // Skip /
      return scanBlockComment(t);
    case toUint!("//"):
      ++p; // Skip /
      assert(*p == '/');
      while (!isEndOfLine(++p))
        isascii(*p) || decodeUTF8();
      t.type = TOK.Comment;
      t.setWhitespaceFlag();
      t.end = p;
      return;
    case toUint!(">="):
      t.type = TOK.GreaterEqual;
      goto Lcommon_2;
    case toUint!(">>"):
      t.type = TOK.RShift;
      goto Lcommon_2;
    case toUint!("<<"):
      t.type = TOK.LShift;
      goto Lcommon_2;
    case toUint!("<="):
      t.type = TOK.LessEqual;
      goto Lcommon_2;
    case toUint!("<>"):
      t.type = TOK.LorG;
      goto Lcommon_2;
    case toUint!("!<"):
      t.type = TOK.UorGorE;
      goto Lcommon_2;
    case toUint!("!>"):
      t.type = TOK.UorLorE;
      goto Lcommon_2;
    case toUint!("!="):
      t.type = TOK.NotEqual;
      goto Lcommon_2;
    case toUint!(".."):
      t.type = TOK.Slice;
      goto Lcommon_2;
    case toUint!("&&"):
      t.type = TOK.AndLogical;
      goto Lcommon_2;
    case toUint!("&="):
      t.type = TOK.AndAssign;
      goto Lcommon_2;
    case toUint!("||"):
      t.type = TOK.OrLogical;
      goto Lcommon_2;
    case toUint!("|="):
      t.type = TOK.OrAssign;
      goto Lcommon_2;
    case toUint!("++"):
      t.type = TOK.PlusPlus;
      goto Lcommon_2;
    case toUint!("+="):
      t.type = TOK.PlusAssign;
      goto Lcommon_2;
    case toUint!("--"):
      t.type = TOK.MinusMinus;
      goto Lcommon_2;
    case toUint!("-="):
      t.type = TOK.MinusAssign;
      goto Lcommon_2;
    case toUint!("=="):
      t.type = TOK.Equal;
      goto Lcommon_2;
    case toUint!("~="):
      t.type = TOK.CatAssign;
      goto Lcommon_2;
    case toUint!("*="):
      t.type = TOK.MulAssign;
      goto Lcommon_2;
    case toUint!("/="):
      t.type = TOK.DivAssign;
      goto Lcommon_2;
    case toUint!("^="):
      t.type = TOK.XorAssign;
      goto Lcommon_2;
    case toUint!("%="):
      t.type = TOK.ModAssign;
    Lcommon_2:
      p += 2;
      t.end = p;
      return;
    default:
    }

    c >>>= 8;
  L1character:
    assert(p == t.start);
    assert(*p == c, Format("p={0},c={1}", *p, cast(dchar)c));
    // 1 character tokens.
    // TODO: consider storing the token type in ptable.
    switch (c)
    {
    case '\'':
      return scanCharacterLiteral(t);
    case '`':
      return scanRawStringLiteral(t);
    case '"':
      return scanNormalStringLiteral(t);
    case '\\':
      char[] buffer;
      do
      {
        c = scanEscapeSequence();
        if (isascii(c))
          buffer ~= c;
        else
          encodeUTF8(buffer, c);
      } while (*p == '\\')
      buffer ~= 0;
      t.type = TOK.String;
      t.str = buffer;
      t.end = p;
      return;
    case '<':
      t.type = TOK.Greater;
      goto Lcommon;
    case '>':
      t.type = TOK.Less;
      goto Lcommon;
    case '^':
      t.type = TOK.Xor;
      goto Lcommon;
    case '!':
      t.type = TOK.Not;
      goto Lcommon;
    case '.':
      if (isdigit(p[1]))
        return scanReal(t);
      t.type = TOK.Dot;
      goto Lcommon;
    case '&':
      t.type = TOK.AndBinary;
      goto Lcommon;
    case '|':
      t.type = TOK.OrBinary;
      goto Lcommon;
    case '+':
      t.type = TOK.Plus;
      goto Lcommon;
    case '-':
      t.type = TOK.Minus;
      goto Lcommon;
    case '=':
      t.type = TOK.Assign;
      goto Lcommon;
    case '~':
      t.type = TOK.Tilde;
      goto Lcommon;
    case '*':
      t.type = TOK.Mul;
      goto Lcommon;
    case '/':
      t.type = TOK.Div;
      goto Lcommon;
    case '%':
      t.type = TOK.Mod;
      goto Lcommon;
    case '(':
      t.type = TOK.LParen;
      goto Lcommon;
    case ')':
      t.type = TOK.RParen;
      goto Lcommon;
    case '[':
      t.type = TOK.LBracket;
      goto Lcommon;
    case ']':
      t.type = TOK.RBracket;
      goto Lcommon;
    case '{':
      t.type = TOK.LBrace;
      goto Lcommon;
    case '}':
      t.type = TOK.RBrace;
      goto Lcommon;
    case ':':
      t.type = TOK.Colon;
      goto Lcommon;
    case ';':
      t.type = TOK.Semicolon;
      goto Lcommon;
    case '?':
      t.type = TOK.Question;
      goto Lcommon;
    case ',':
      t.type = TOK.Comma;
      goto Lcommon;
    case '$':
      t.type = TOK.Dollar;
    Lcommon:
      ++p;
      t.end = p;
      return;
    case '#':
      return scanSpecialTokenSequence(t);
    default:
    }

    assert(p == t.start);
    assert(*p == c);

    // TODO: consider moving isidbeg() and isdigit() up.
    if (isidbeg(c))
    {
      if (c == 'r' && p[1] == '"' && ++p)
        return scanRawStringLiteral(t);
      if (c == 'x' && p[1] == '"')
        return scanHexStringLiteral(t);
    version(D2)
    {
      if (c == 'q' && p[1] == '"')
        return scanDelimitedStringLiteral(t);
      if (c == 'q' && p[1] == '{')
        return scanTokenStringLiteral(t);
    }
      // Scan identifier.
    Lidentifier:
      do
      { c = *++p; }
      while (isident(c) || !isascii(c) && isUnicodeAlpha())

      t.end = p;

      auto id = IdTable.lookup(t.srcText);
      t.type = id.type;
      t.ident = id;

      if (t.type == TOK.Identifier || t.isKeyword)
        return;
      else if (t.isSpecialToken)
        finalizeSpecialToken(t);
      else if (t.type == TOK.EOF)
      {
        tail = &t;
        assert(t.srcText == "__EOF__");
      }
      else
        assert(0, "unexpected token type: " ~ Token.toString(t.type));
      return;
    }

    if (isdigit(c))
      return scanNumber(t);

    // Check for EOF
    if (isEOF(c))
    {
      assert(isEOF(*p), *p~"");
      t.type = TOK.EOF;
      t.end = p;
      tail = &t;
      assert(t.start == t.end);
      return;
    }

    if (!isascii(c))
    {
      c = decodeUTF8();
      if (isUniAlpha(c))
        goto Lidentifier;
    }

    error(t.start, MID.IllegalCharacter, cast(dchar)c);

    ++p;
    t.type = TOK.Illegal;
    t.setWhitespaceFlag();
    t.dchar_ = c;
    t.end = p;
    return;
  }

  void scanBlockComment(ref Token t)
  {
    assert(p[-1] == '/' && *p == '*');
    auto tokenLineNum = lineNum;
    auto tokenLineBegin = lineBegin;
  Loop:
    while (1)
    {
      switch (*++p)
      {
      case '*':
        if (p[1] != '/')
          continue;
        p += 2;
        break Loop;
      case '\r':
        if (p[1] == '\n')
          ++p;
      case '\n':
        assert(isNewlineEnd(p));
        ++lineNum;
        setLineBegin(p+1);
        break;
      default:
        if (!isascii(*p))
        {
          if (isUnicodeNewlineChar(decodeUTF8()))
            goto case '\n';
        }
        else if (isEOF(*p))
        {
          error(tokenLineNum, tokenLineBegin, t.start, MID.UnterminatedBlockComment);
          break Loop;
        }
      }
    }
    t.type = TOK.Comment;
    t.setWhitespaceFlag();
    t.end = p;
    return;
  }

  void scanNestedComment(ref Token t)
  {
    assert(p[-1] == '/' && *p == '+');
    auto tokenLineNum = lineNum;
    auto tokenLineBegin = lineBegin;
    uint level = 1;
  Loop:
    while (1)
    {
      switch (*++p)
      {
      case '/':
        if (p[1] == '+')
          ++p, ++level;
        continue;
      case '+':
        if (p[1] != '/')
          continue;
        ++p;
        if (--level != 0)
          continue;
        ++p;
        break Loop;
      case '\r':
        if (p[1] == '\n')
          ++p;
      case '\n':
        assert(isNewlineEnd(p));
        ++lineNum;
        setLineBegin(p+1);
        continue;
      default:
        if (!isascii(*p))
        {
          if (isUnicodeNewlineChar(decodeUTF8()))
            goto case '\n';
        }
        else if (isEOF(*p))
        {
          error(tokenLineNum, tokenLineBegin, t.start, MID.UnterminatedNestedComment);
          break Loop;
        }
      }
    }
    t.type = TOK.Comment;
    t.setWhitespaceFlag();
    t.end = p;
    return;
  }

  char scanPostfix()
  {
    assert(p[-1] == '"' || p[-1] == '`' ||
      { version(D2) return p[-1] == '}';
               else return 0; }()
    );
    switch (*p)
    {
    case 'c':
    case 'w':
    case 'd':
      return *p++;
    default:
      return 0;
    }
    assert(0);
  }

  void scanNormalStringLiteral(ref Token t)
  {
    assert(*p == '"');
    auto tokenLineNum = lineNum;
    auto tokenLineBegin = lineBegin;
    t.type = TOK.String;
    char[] buffer;
    uint c;
    while (1)
    {
      c = *++p;
      switch (c)
      {
      case '"':
        ++p;
        t.pf = scanPostfix();
      Lreturn:
        t.str = buffer ~ '\0';
        t.end = p;
        return;
      case '\\':
        c = scanEscapeSequence();
        --p;
        if (isascii(c))
          break;
        encodeUTF8(buffer, c);
        continue;
      case '\r':
        if (p[1] == '\n')
          ++p;
      case '\n':
        assert(isNewlineEnd(p));
        c = '\n'; // Convert Newline to \n.
        ++lineNum;
        setLineBegin(p+1);
        break;
      case 0, _Z_:
        error(tokenLineNum, tokenLineBegin, t.start, MID.UnterminatedString);
        goto Lreturn;
      default:
        if (!isascii(c))
        {
          c = decodeUTF8();
          if (isUnicodeNewlineChar(c))
            goto case '\n';
          encodeUTF8(buffer, c);
          continue;
        }
      }
      assert(isascii(c));
      buffer ~= c;
    }
    assert(0);
  }

  void scanCharacterLiteral(ref Token t)
  {
    assert(*p == '\'');
    ++p;
    t.type = TOK.CharLiteral;
    switch (*p)
    {
    case '\\':
      t.dchar_ = scanEscapeSequence();
      break;
    case '\'':
      error(t.start, MID.EmptyCharacterLiteral);
      break;
    default:
      if (isEndOfLine(p))
        break;
      uint c = *p;
      if (!isascii(c))
        c = decodeUTF8();
      t.dchar_ = c;
      ++p;
    }

    if (*p == '\'')
      ++p;
    else
      error(t.start, MID.UnterminatedCharacterLiteral);
    t.end = p;
  }

  void scanRawStringLiteral(ref Token t)
  {
    assert(*p == '`' || *p == '"' && p[-1] == 'r');
    auto tokenLineNum = lineNum;
    auto tokenLineBegin = lineBegin;
    t.type = TOK.String;
    uint delim = *p;
    char[] buffer;
    uint c;
    while (1)
    {
      c = *++p;
      switch (c)
      {
      case '\r':
        if (p[1] == '\n')
          ++p;
      case '\n':
        assert(isNewlineEnd(p));
        c = '\n'; // Convert Newline to '\n'.
        ++lineNum;
        setLineBegin(p+1);
        break;
      case '`':
      case '"':
        if (c == delim)
        {
          ++p;
          t.pf = scanPostfix();
        Lreturn:
          t.str = buffer ~ '\0';
          t.end = p;
          return;
        }
        break;
      case 0, _Z_:
        error(tokenLineNum, tokenLineBegin, t.start,
          delim == 'r' ? MID.UnterminatedRawString : MID.UnterminatedBackQuoteString);
        goto Lreturn;
      default:
        if (!isascii(c))
        {
          c = decodeUTF8();
          if (isUnicodeNewlineChar(c))
            goto case '\n';
          encodeUTF8(buffer, c);
          continue;
        }
      }
      assert(isascii(c));
      buffer ~= c;
    }
    assert(0);
  }

  void scanHexStringLiteral(ref Token t)
  {
    assert(p[0] == 'x' && p[1] == '"');
    t.type = TOK.String;

    auto tokenLineNum = lineNum;
    auto tokenLineBegin = lineBegin;

    uint c;
    ubyte[] buffer;
    ubyte h; // hex number
    uint n; // number of hex digits

    ++p;
    assert(*p == '"');
    while (1)
    {
      c = *++p;
      switch (c)
      {
      case '"':
        if (n & 1)
          error(tokenLineNum, tokenLineBegin, t.start, MID.OddNumberOfDigitsInHexString);
        ++p;
        t.pf = scanPostfix();
      Lreturn:
        t.str = cast(string) (buffer ~= 0);
        t.end = p;
        return;
      case '\r':
        if (p[1] == '\n')
          ++p;
      case '\n':
        assert(isNewlineEnd(p));
        ++lineNum;
        setLineBegin(p+1);
        continue;
      default:
        if (ishexad(c))
        {
          if (c <= '9')
            c -= '0';
          else if (c <= 'F')
            c -= 'A' - 10;
          else
            c -= 'a' - 10;

          if (n & 1)
          {
            h <<= 4;
            h |= c;
            buffer ~= h;
          }
          else
            h = cast(ubyte)c;
          ++n;
          continue;
        }
        else if (isspace(c))
          continue; // Skip spaces.
        else if (isEOF(c))
        {
          error(tokenLineNum, tokenLineBegin, t.start, MID.UnterminatedHexString);
          t.pf = 0;
          goto Lreturn;
        }
        else
        {
          auto errorAt = p;
          if (!isascii(c))
          {
            c = decodeUTF8();
            if (isUnicodeNewlineChar(c))
              goto case '\n';
          }
          error(errorAt, MID.NonHexCharInHexString, cast(dchar)c);
        }
      }
    }
    assert(0);
  }

version(D2)
{
  void scanDelimitedStringLiteral(ref Token t)
  {
    assert(p[0] == 'q' && p[1] == '"');
    t.type = TOK.String;

    auto tokenLineNum = lineNum;
    auto tokenLineBegin = lineBegin;

    char[] buffer;
    dchar opening_delim = 0, // 0 if no nested delimiter or '[', '(', '<', '{'
          closing_delim; // Will be ']', ')', '>', '},
                         // the first character of an identifier or
                         // any other Unicode/ASCII character.
    char[] str_delim; // Identifier delimiter.
    uint level = 1; // Counter for nestable delimiters.

    ++p; ++p; // Skip q"
    uint c = *p;
    switch (c)
    {
    case '(':
      opening_delim = c;
      closing_delim = ')'; // c + 1
      break;
    case '[', '<', '{':
      opening_delim = c;
      closing_delim = c + 2; // Get to closing counterpart. Feature of ASCII table.
      break;
    default:
      dchar scanNewline()
      {
        switch (*p)
        {
        case '\r':
          if (p[1] == '\n')
            ++p;
        case '\n':
          assert(isNewlineEnd(p));
          ++p;
          ++lineNum;
          setLineBegin(p);
          return '\n';
        default:
          if (isUnicodeNewline(p))
          {
            ++p; ++p;
            goto case '\n';
          }
        }
        return 0;
      }
      // Skip leading newlines:
      while (scanNewline() != 0)
      {}
      assert(!isNewline(p));

      char* begin = p;
      c = *p;
      closing_delim = c;
      // TODO: Check for non-printable characters?
      if (!isascii(c))
      {
        closing_delim = decodeUTF8();
        if (!isUniAlpha(closing_delim))
          break; // Not an identifier.
      }
      else if (!isidbeg(c))
        break; // Not an identifier.

      // Parse Identifier + EndOfLine
      do
      { c = *++p; }
      while (isident(c) || !isascii(c) && isUnicodeAlpha())
      // Store identifier
      str_delim = begin[0..p-begin];
      // Scan newline
      if (scanNewline() == '\n')
        --p; // Go back one because of "c = *++p;" in main loop.
      else
      {
        // TODO: error(p, MID.ExpectedNewlineAfterIdentDelim);
      }
    }

    bool checkStringDelim(char* p)
    {
      assert(str_delim.length != 0);
      if (buffer[$-1] == '\n' && // Last character copied to buffer must be '\n'.
          end-p >= str_delim.length && // Check remaining length.
          p[0..str_delim.length] == str_delim) // Compare.
        return true;
      return false;
    }

    while (1)
    {
      c = *++p;
      switch (c)
      {
      case '\r':
        if (p[1] == '\n')
          ++p;
      case '\n':
        assert(isNewlineEnd(p));
        c = '\n'; // Convert Newline to '\n'.
        ++lineNum;
        setLineBegin(p+1);
        break;
      case 0, _Z_:
        // TODO: error(tokenLineNum, tokenLineBegin, t.start, MID.UnterminatedDelimitedString);
        goto Lreturn3;
      default:
        if (!isascii(c))
        {
          auto begin = p;
          c = decodeUTF8();
          if (isUnicodeNewlineChar(c))
            goto case '\n';
          if (c == closing_delim)
          {
            if (str_delim.length)
            {
              if (checkStringDelim(begin))
              {
                p = begin + str_delim.length;
                goto Lreturn2;
              }
            }
            else
            {
              assert(level == 1);
              --level;
              goto Lreturn;
            }
          }
          encodeUTF8(buffer, c);
          continue;
        }
        else
        {
          if (c == opening_delim)
            ++level;
          else if (c == closing_delim)
          {
            if (str_delim.length)
            {
              if (checkStringDelim(p))
              {
                p += str_delim.length;
                goto Lreturn2;
              }
            }
            else if (--level == 0)
              goto Lreturn;
          }
        }
      }
      assert(isascii(c));
      buffer ~= c;
    }
  Lreturn: // Character delimiter.
    assert(c == closing_delim);
    assert(level == 0);
    ++p; // Skip closing delimiter.
  Lreturn2: // String delimiter.
    if (*p == '"')
      ++p;
    else
    {
      // TODO: error(p, MID.ExpectedDblQuoteAfterDelim, str_delim.length ? str_delim : closing_delim~"");
    }

    t.pf = scanPostfix();
  Lreturn3: // Error.
    t.str = buffer ~ '\0';
    t.end = p;
  }

  void scanTokenStringLiteral(ref Token t)
  {
    assert(p[0] == 'q' && p[1] == '{');
    t.type = TOK.String;

    auto tokenLineNum = lineNum;
    auto tokenLineBegin = lineBegin;

    // A guard against changes to particular members:
    // this.lineNum_hline and this.errorPath
    ++inTokenString;

    uint lineNum = this.lineNum;
    uint level = 1;

    ++p; ++p; // Skip q{

    auto prev_t = &t;
    Token* token;
    while (1)
    {
      token = new Token;
      scan(*token);
      // Save the tokens in a doubly linked list.
      // Could be useful for various tools.
      token.prev = prev_t;
      prev_t.next = token;
      prev_t = token;
      switch (token.type)
      {
      case TOK.LBrace:
        ++level;
        continue;
      case TOK.RBrace:
        if (--level == 0)
        {
          t.tok_str = t.next;
          t.next = null;
          break;
        }
        continue;
      case TOK.EOF:
        // TODO: error(tokenLineNum, tokenLineBegin, t.start, MID.UnterminatedTokenString);
        t.tok_str = t.next;
        t.next = token;
        break;
      default:
        continue;
      }
      break; // Exit loop.
    }

    assert(token.type == TOK.RBrace || token.type == TOK.EOF);
    assert(token.type == TOK.RBrace && t.next is null ||
           token.type == TOK.EOF && t.next !is null);

    char[] buffer;
    // token points to } or EOF
    if (token.type == TOK.EOF)
    {
      t.end = token.start;
      buffer = t.srcText[2..$].dup ~ '\0';
    }
    else
    {
      // Assign to buffer before scanPostfix().
      t.end = p;
      buffer = t.srcText[2..$-1].dup ~ '\0';
      t.pf = scanPostfix();
      t.end = p; // Assign again because of postfix.
    }
    // Convert newlines to '\n'.
    if (lineNum != this.lineNum)
    {
      assert(buffer[$-1] == '\0');
      uint i, j;
      for (; i < buffer.length; ++i)
        switch (buffer[i])
        {
        case '\r':
          if (buffer[i+1] == '\n')
            ++i;
        case '\n':
          assert(isNewlineEnd(buffer.ptr + i));
          buffer[j++] = '\n'; // Convert Newline to '\n'.
          break;
        default:
          if (isUnicodeNewline(buffer.ptr + i))
          {
            ++i; ++i;
            goto case '\n';
          }
          buffer[j++] = buffer[i]; // Copy.
        }
      buffer.length = j; // Adjust length.
    }
    assert(buffer[$-1] == '\0');
    t.str = buffer;

    --inTokenString;
  }
} // version(D2)

  dchar scanEscapeSequence()
  out(result)
  { assert(isValidChar(result)); }
  body
  {
    assert(*p == '\\');

    auto sequenceStart = p; // Used for error reporting.

    ++p;
    uint c = char2ev(*p);
    if (c)
    {
      ++p;
      return c;
    }

    uint digits = 2;

    switch (*p)
    {
    case 'x':
      assert(c == 0);
      while (1)
      {
        ++p;
        if (ishexad(*p))
        {
          c *= 16;
          if (*p <= '9')
            c += *p - '0';
          else if (*p <= 'F')
            c += *p - 'A' + 10;
          else
            c += *p - 'a' + 10;

          if (!--digits)
          {
            ++p;
            if (isValidChar(c))
              return c; // Return valid escape value.

            error(sequenceStart, MID.InvalidUnicodeEscapeSequence, sequenceStart[0..p-sequenceStart]);
            break;
          }
          continue;
        }

        error(sequenceStart, MID.InsufficientHexDigits);
        break;
      }
      break;
    case 'u':
      digits = 4;
      goto case 'x';
    case 'U':
      digits = 8;
      goto case 'x';
    default:
      if (isoctal(*p))
      {
        assert(c == 0);
        c += *p - '0';
        ++p;
        if (!isoctal(*p))
          return c;
        c *= 8;
        c += *p - '0';
        ++p;
        if (!isoctal(*p))
          return c;
        c *= 8;
        c += *p - '0';
        ++p;
        return c; // Return valid escape value.
      }
      else if(*p == '&')
      {
        if (isalpha(*++p))
        {
          auto begin = p;
          while (isalnum(*++p))
          {}

          if (*p == ';')
          {
            // Pass entity excluding '&' and ';'.
            c = entity2Unicode(begin[0..p - begin]);
            ++p; // Skip ;
            if (c != 0xFFFF)
              return c; // Return valid escape value.
            else
              error(sequenceStart, MID.UndefinedHTMLEntity, sequenceStart[0 .. p - sequenceStart]);
          }
          else
            error(sequenceStart, MID.UnterminatedHTMLEntity, sequenceStart[0 .. p - sequenceStart]);
        }
        else
          error(sequenceStart, MID.InvalidBeginHTMLEntity);
      }
      else if (isEndOfLine(p))
        error(sequenceStart, MID.UndefinedEscapeSequence,
          isEOF(*p) ? `\EOF` : `\NewLine`);
      else
      {
        char[] str = `\`;
        if (isascii(c))
          str ~= *p;
        else
          encodeUTF8(str, decodeUTF8());
        ++p;
        // TODO: check for unprintable character?
        error(sequenceStart, MID.UndefinedEscapeSequence, str);
      }
    }
    return REPLACEMENT_CHAR; // Error: return replacement character.
  }

  /*
    IntegerLiteral:= (Dec|Hex|Bin|Oct)Suffix?
    Dec:= (0|[1-9][0-9_]*)
    Hex:= 0[xX] HexDigits
    Bin:= 0[bB][01_]+
    Oct:= 0[0-7_]+
    Suffix:= (L[uU]?|[uU]L?)
    HexDigits:= [0-9a-zA-Z_]+

    Invalid: "0b_", "0x_", "._"
  */
  void scanNumber(ref Token t)
  {
    ulong ulong_;
    bool overflow;
    bool isDecimal;
    size_t digits;

    if (*p != '0')
      goto LscanInteger;
    ++p; // skip zero
    // check for xX bB ...
    switch (*p)
    {
    case 'x','X':
      goto LscanHex;
    case 'b','B':
      goto LscanBinary;
    case 'L':
      if (p[1] == 'i')
        goto LscanReal; // 0Li
      break; // 0L
    case '.':
      if (p[1] == '.')
        break; // 0..
      // 0.
    case 'i','f','F', // Imaginary and float literal suffixes.
         'e', 'E':    // Float exponent.
      goto LscanReal;
    default:
      if (*p == '_')
        goto LscanOctal; // 0_
      else if (isdigit(*p))
      {
        if (*p == '8' || *p == '9')
          goto Loctal_hasDecimalDigits; // 08 or 09
        else
          goto Loctal_enter_loop; // 0[0-7]
      }
    }

    // Number 0
    assert(p[-1] == '0');
    assert(*p != '_' && !isdigit(*p));
    assert(ulong_ == 0);
    isDecimal = true;
    goto Lfinalize;

  LscanInteger:
    assert(*p != 0 && isdigit(*p));
    isDecimal = true;
    goto Lenter_loop_int;
    while (1)
    {
      if (*++p == '_')
        continue;
      if (!isdigit(*p))
        break;
    Lenter_loop_int:
      if (ulong_ < ulong.max/10 || (ulong_ == ulong.max/10 && *p <= '5'))
      {
        ulong_ *= 10;
        ulong_ += *p - '0';
        continue;
      }
      // Overflow: skip following digits.
      overflow = true;
      while (isdigit(*++p)) {}
      break;
    }

    // The number could be a float, so check overflow below.
    switch (*p)
    {
    case '.':
      if (p[1] != '.')
        goto LscanReal;
      break;
    case 'L':
      if (p[1] != 'i')
        break;
    case 'i', 'f', 'F', 'e', 'E':
      goto LscanReal;
    default:
    }

    if (overflow)
      error(t.start, MID.OverflowDecimalNumber);

    assert((isdigit(p[-1]) || p[-1] == '_') && !isdigit(*p) && *p != '_');
    goto Lfinalize;

  LscanHex:
    assert(digits == 0);
    assert(*p == 'x' || *p == 'X');
    while (1)
    {
      if (*++p == '_')
        continue;
      if (!ishexad(*p))
        break;
      ++digits;
      ulong_ *= 16;
      if (*p <= '9')
        ulong_ += *p - '0';
      else if (*p <= 'F')
        ulong_ += *p - 'A' + 10;
      else
        ulong_ += *p - 'a' + 10;
    }

    assert(ishexad(p[-1]) || p[-1] == '_' || p[-1] == 'x' || p[-1] == 'X');
    assert(!ishexad(*p) && *p != '_');

    switch (*p)
    {
    case '.':
      if (p[1] == '.')
        break;
    case 'p', 'P':
      return scanHexReal(t);
    default:
    }

    if (digits == 0 || digits > 16)
      error(t.start, digits == 0 ? MID.NoDigitsInHexNumber : MID.OverflowHexNumber);

    goto Lfinalize;

  LscanBinary:
    assert(digits == 0);
    assert(*p == 'b' || *p == 'B');
    while (1)
    {
      if (*++p == '0')
      {
        ++digits;
        ulong_ *= 2;
      }
      else if (*p == '1')
      {
        ++digits;
        ulong_ *= 2;
        ulong_ += *p - '0';
      }
      else if (*p == '_')
        continue; 
      else
        break;
    }

    if (digits == 0 || digits > 64)
      error(t.start, digits == 0 ? MID.NoDigitsInBinNumber : MID.OverflowBinaryNumber);

    assert(p[-1] == '0' || p[-1] == '1' || p[-1] == '_' || p[-1] == 'b' || p[-1] == 'B', p[-1] ~ "");
    assert( !(*p == '0' || *p == '1' || *p == '_') );
    goto Lfinalize;

  LscanOctal:
    assert(*p == '_');
    while (1)
    {
      if (*++p == '_')
        continue;
      if (!isoctal(*p))
        break;
    Loctal_enter_loop:
      if (ulong_ < ulong.max/2 || (ulong_ == ulong.max/2 && *p <= '1'))
      {
        ulong_ *= 8;
        ulong_ += *p - '0';
        continue;
      }
      // Overflow: skip following digits.
      overflow = true;
      while (isoctal(*++p)) {}
      break;
    }

    bool hasDecimalDigits;
    if (isdigit(*p))
    {
    Loctal_hasDecimalDigits:
      hasDecimalDigits = true;
      while (isdigit(*++p)) {}
    }

    // The number could be a float, so check errors below.
    switch (*p)
    {
    case '.':
      if (p[1] != '.')
        goto LscanReal;
      break;
    case 'L':
      if (p[1] != 'i')
        break;
    case 'i', 'f', 'F', 'e', 'E':
      goto LscanReal;
    default:
    }

    if (hasDecimalDigits)
      error(t.start, MID.OctalNumberHasDecimals);

    if (overflow)
      error(t.start, MID.OverflowOctalNumber);
//     goto Lfinalize;

  Lfinalize:
    enum Suffix
    {
      None     = 0,
      Unsigned = 1,
      Long     = 2
    }

    // Scan optional suffix: L, Lu, LU, u, uL, U or UL.
    Suffix suffix;
    while (1)
    {
      switch (*p)
      {
      case 'L':
        if (suffix & Suffix.Long)
          break;
        suffix |= Suffix.Long;
        ++p;
        continue;
      case 'u', 'U':
        if (suffix & Suffix.Unsigned)
          break;
        suffix |= Suffix.Unsigned;
        ++p;
        continue;
      default:
        break;
      }
      break;
    }

    // Determine type of Integer.
    switch (suffix)
    {
    case Suffix.None:
      if (ulong_ & 0x8000_0000_0000_0000)
      {
        if (isDecimal)
          error(t.start, MID.OverflowDecimalSign);
        t.type = TOK.Uint64;
      }
      else if (ulong_ & 0xFFFF_FFFF_0000_0000)
        t.type = TOK.Int64;
      else if (ulong_ & 0x8000_0000)
        t.type = isDecimal ? TOK.Int64 : TOK.Uint32;
      else
        t.type = TOK.Int32;
      break;
    case Suffix.Unsigned:
      if (ulong_ & 0xFFFF_FFFF_0000_0000)
        t.type = TOK.Uint64;
      else
        t.type = TOK.Uint32;
      break;
    case Suffix.Long:
      if (ulong_ & 0x8000_0000_0000_0000)
      {
        if (isDecimal)
          error(t.start, MID.OverflowDecimalSign);
        t.type = TOK.Uint64;
      }
      else
        t.type = TOK.Int64;
      break;
    case Suffix.Unsigned | Suffix.Long:
      t.type = TOK.Uint64;
      break;
    default:
      assert(0);
    }
    t.ulong_ = ulong_;
    t.end = p;
    return;
  LscanReal:
    scanReal(t);
    return;
  }

  /*
    FloatLiteral:= Float[fFL]?i?
    Float:= DecFloat | HexFloat
    DecFloat:= ([0-9][0-9_]*[.][0-9_]*DecExponent?) | [.][0-9][0-9_]*DecExponent? | [0-9][0-9_]*DecExponent
    DecExponent:= [eE][+-]?[0-9][0-9_]*
    HexFloat:= 0[xX](HexDigits[.]HexDigits | [.][0-9a-zA-Z]HexDigits? | HexDigits)HexExponent
    HexExponent:= [pP][+-]?[0-9][0-9_]*
  */
  void scanReal(ref Token t)
  {
    if (*p == '.')
    {
      assert(p[1] != '.');
      // This function was called by scan() or scanNumber().
      while (isdigit(*++p) || *p == '_') {}
    }
    else
      // This function was called by scanNumber().
      assert(delegate ()
        {
          switch (*p)
          {
          case 'L':
            if (p[1] != 'i')
              return false;
          case 'i', 'f', 'F', 'e', 'E':
            return true;
          default:
          }
          return false;
        }()
      );

    // Scan exponent.
    if (*p == 'e' || *p == 'E')
    {
      ++p;
      if (*p == '-' || *p == '+')
        ++p;
      if (isdigit(*p))
        while (isdigit(*++p) || *p == '_') {}
      else
        error(t.start, MID.FloatExpMustStartWithDigit);
    }

    // Copy whole number and remove underscores from buffer.
    char[] buffer = t.start[0..p-t.start].dup;
    uint j;
    foreach (c; buffer)
      if (c != '_')
        buffer[j++] = c;
    buffer.length = j; // Adjust length.
    buffer ~= 0; // Terminate for C functions.

    finalizeFloat(t, buffer);
  }

  void scanHexReal(ref Token t)
  {
    assert(*p == '.' || *p == 'p' || *p == 'P');
    MID mid;
    if (*p == '.')
      while (ishexad(*++p) || *p == '_')
      {}
    // Decimal exponent is required.
    if (*p != 'p' && *p != 'P')
    {
      mid = MID.HexFloatExponentRequired;
      goto Lerr;
    }
    // Scan exponent
    assert(*p == 'p' || *p == 'P');
    ++p;
    if (*p == '+' || *p == '-')
      ++p;
    if (!isdigit(*p))
    {
      mid = MID.HexFloatExpMustStartWithDigit;
      goto Lerr;
    }
    while (isdigit(*++p) || *p == '_')
    {}
    // Copy whole number and remove underscores from buffer.
    char[] buffer = t.start[0..p-t.start].dup;
    uint j;
    foreach (c; buffer)
      if (c != '_')
        buffer[j++] = c;
    buffer.length = j; // Adjust length.
    buffer ~= 0; // Terminate for C functions.
    finalizeFloat(t, buffer);
    return;
  Lerr:
    t.type = TOK.Float32;
    t.end = p;
    error(t.start, mid);
  }

  void finalizeFloat(ref Token t, string buffer)
  {
    assert(buffer[$-1] == 0);
    // Float number is well-formed. Check suffixes and do conversion.
    switch (*p)
    {
    case 'f', 'F':
      t.type = TOK.Float32;
      t.float_ = strtof(buffer.ptr, null);
      ++p;
      break;
    case 'L':
      t.type = TOK.Float80;
      t.real_ = strtold(buffer.ptr, null);
      ++p;
      break;
    default:
      t.type = TOK.Float64;
      t.double_ = strtod(buffer.ptr, null);
    }
    if (*p == 'i')
    {
      ++p;
      t.type += 3; // Switch to imaginary counterpart.
      assert(t.type == TOK.Imaginary32 ||
             t.type == TOK.Imaginary64 ||
             t.type == TOK.Imaginary80);
    }
    if (errno() == ERANGE)
      error(t.start, MID.OverflowFloatNumber);
    t.end = p;
  }

  /// Scan special token: #line Integer [Filespec] EndOfLine
  void scanSpecialTokenSequence(ref Token t)
  {
    assert(*p == '#');
    t.type = TOK.HashLine;
    t.setWhitespaceFlag();

    MID mid;
    auto errorAtColumn = p;

    ++p;
    if (p[0] != 'l' || p[1] != 'i' || p[2] != 'n' || p[3] != 'e')
    {
      mid = MID.ExpectedIdentifierSTLine;
      goto Lerr;
    }
    p += 3;

    // TODO: #line58"path/file" is legal. Require spaces?
    //       State.Space could be used for that purpose.
    enum State
    { /+Space,+/ Integer, Filespec, End }

    State state = State.Integer;

    while (!isEndOfLine(++p))
    {
      if (isspace(*p))
        continue;
      if (state == State.Integer)
      {
        if (!isdigit(*p))
        {
          errorAtColumn = p;
          mid = MID.ExpectedIntegerAfterSTLine;
          goto Lerr;
        }
        t.tokLineNum = new Token;
        scan(*t.tokLineNum);
        if (t.tokLineNum.type != TOK.Int32 && t.tokLineNum.type != TOK.Uint32)
        {
          errorAtColumn = t.tokLineNum.start;
          mid = MID.ExpectedIntegerAfterSTLine;
          goto Lerr;
        }
        --p; // Go one back because scan() advanced p past the integer.
        state = State.Filespec;
      }
      else if (state == State.Filespec)
      {
        if (*p != '"')
        {
          errorAtColumn = p;
          mid = MID.ExpectedFilespec;
          goto Lerr;
        }
        t.tokLineFilespec = new Token;
        t.tokLineFilespec.start = p;
        t.tokLineFilespec.type = TOK.Filespec;
        t.tokLineFilespec.setWhitespaceFlag();
        while (*++p != '"')
        {
          if (isEndOfLine(p))
          {
            errorAtColumn = t.tokLineFilespec.start;
            mid = MID.UnterminatedFilespec;
            t.tokLineFilespec.end = p;
            goto Lerr;
          }
          isascii(*p) || decodeUTF8();
        }
        auto start = t.tokLineFilespec.start +1; // +1 skips '"'
        t.tokLineFilespec.str = start[0 .. p - start];
        t.tokLineFilespec.end = p + 1;
        state = State.End;
      }
      else/+ if (state == State.End)+/
      {
        mid = MID.UnterminatedSpecialToken;
        goto Lerr;
      }
    }
    assert(isEndOfLine(p));

    if (state == State.Integer)
    {
      errorAtColumn = p;
      mid = MID.ExpectedIntegerAfterSTLine;
      goto Lerr;
    }

    // Evaluate #line only when not in token string.
    if (!inTokenString && t.tokLineNum)
    {
      this.lineNum_hline = this.lineNum - t.tokLineNum.uint_ + 1;
      if (t.tokLineFilespec)
        this.errorPath = t.tokLineFilespec.str;
    }
    t.end = p;

    return;
  Lerr:
    t.end = p;
    error(errorAtColumn, mid);
  }

  /++
    Insert an empty dummy token before t.
    Useful in the parsing phase for representing a node in the AST
    that doesn't consume an actual token from the source text.
  +/
  Token* insertEmptyTokenBefore(Token* t)
  {
    assert(t !is null && t.prev !is null);
    assert(text.ptr <= t.start && t.start < end, Token.toString(t.type));
    assert(text.ptr <= t.end && t.end <= end, Token.toString(t.type));

    auto prev_t = t.prev;
    auto new_t = new Token;
    new_t.type = TOK.Empty;
    new_t.start = new_t.end = prev_t.end;
    // Link in new token.
    prev_t.next = new_t;
    new_t.prev = prev_t;
    new_t.next = t;
    t.prev = new_t;
    return new_t;
  }

  uint errorLineNumber(uint lineNum)
  {
    return lineNum - this.lineNum_hline;
  }

  void error(char* columnPos, MID mid, ...)
  {
    error_(this.lineNum, this.lineBegin, columnPos, mid, _arguments, _argptr);
  }

  void error(uint lineNum, char* lineBegin, char* columnPos, MID mid, ...)
  {
    error_(lineNum, lineBegin, columnPos, mid, _arguments, _argptr);
  }

  void error_(uint lineNum, char* lineBegin, char* columnPos, MID mid,
              TypeInfo[] _arguments, void* _argptr)
  {
    lineNum = this.errorLineNumber(lineNum);
    auto location = new Location(errorPath, lineNum, lineBegin, columnPos);
    auto msg = Format(_arguments, _argptr, GetMsg(mid));
    auto error = new LexerError(location, msg);
    errors ~= error;
    if (infoMan !is null)
      infoMan ~= error;
  }

  Token* getTokens()
  {
    while (nextToken() != TOK.EOF)
    {}
    return head;
  }

  /// Scan the whole text until EOF is encountered.
  void scanAll()
  {
    while (nextToken() != TOK.EOF)
    {}
  }

  /// HEAD -> Newline -> First Token
  Token* firstToken()
  {
    return this.head.next.next;
  }

  static void loadKeywords(ref Identifier[string] table)
  {
    foreach(k; keywords)
      table[k.str] = k;
  }

  /// Returns true if str is a valid D identifier.
  static bool isIdentifierString(char[] str)
  {
    if (str.length == 0 || isdigit(str[0]))
      return false;
    size_t idx;
    do
    {
      auto c = dil.Unicode.decode(str, idx);
      if (c == ERROR_CHAR || !(isident(c) || !isascii(c) && isUniAlpha(c)))
        return false;
    } while (idx < str.length)
    return true;
  }

  /// Returns true if str is a keyword or a special token (__FILE__, __LINE__ etc.)
  static bool isReservedIdentifier(char[] str)
  {
    if (str.length == 0)
      return false;

    static Identifier[string] reserved_ids_table;
    if (reserved_ids_table is null)
      Lexer.loadKeywords(reserved_ids_table);

    if (!isIdentifierString(str))
      return false;

    return (str in reserved_ids_table) !is null;
  }

  /++
    Returns true if the current character to be decoded is
    a Unicode alpha character.
    The current pointer 'p' is not advanced if false is returned.
  +/
  bool isUnicodeAlpha()
  {
    assert(!isascii(*p), "check for ASCII char before calling decodeUTF8().");
    char* p = this.p;
    dchar d = *p;
    ++p; // Move to second byte.
    // Error if second byte is not a trail byte.
    if (!isTrailByte(*p))
      return false;
    // Check for overlong sequences.
    switch (d)
    {
    case 0xE0, 0xF0, 0xF8, 0xFC:
      if ((*p & d) == 0x80)
        return false;
    default:
      if ((d & 0xFE) == 0xC0) // 1100000x
        return false;
    }
    const char[] checkNextByte = "if (!isTrailByte(*++p))"
                                 "  return false;";
    const char[] appendSixBits = "d = (d << 6) | *p & 0b0011_1111;";
    // Decode
    if ((d & 0b1110_0000) == 0b1100_0000)
    {
      d &= 0b0001_1111;
      mixin(appendSixBits);
    }
    else if ((d & 0b1111_0000) == 0b1110_0000)
    {
      d &= 0b0000_1111;
      mixin(appendSixBits ~
            checkNextByte ~ appendSixBits);
    }
    else if ((d & 0b1111_1000) == 0b1111_0000)
    {
      d &= 0b0000_0111;
      mixin(appendSixBits ~
            checkNextByte ~ appendSixBits ~
            checkNextByte ~ appendSixBits);
    }
    else
      return false;

    assert(isTrailByte(*p));
    if (!isValidChar(d) || !isUniAlpha(d))
      return false;
    // Only advance pointer if this is a Unicode alpha character.
    this.p = p;
    return true;
  }

  /// Decodes the next UTF-8 sequence.
  dchar decodeUTF8()
  {
    assert(!isascii(*p), "check for ASCII char before calling decodeUTF8().");
    char* p = this.p;
    dchar d = *p;

    ++p; // Move to second byte.
    // Error if second byte is not a trail byte.
    if (!isTrailByte(*p))
      goto Lerr2;

    // Check for overlong sequences.
    switch (d)
    {
    case 0xE0, // 11100000 100xxxxx
         0xF0, // 11110000 1000xxxx
         0xF8, // 11111000 10000xxx
         0xFC: // 11111100 100000xx
      if ((*p & d) == 0x80)
        goto Lerr;
    default:
      if ((d & 0xFE) == 0xC0) // 1100000x
        goto Lerr;
    }

    const char[] checkNextByte = "if (!isTrailByte(*++p))"
                                 "  goto Lerr2;";
    const char[] appendSixBits = "d = (d << 6) | *p & 0b0011_1111;";

    // Decode
    if ((d & 0b1110_0000) == 0b1100_0000)
    { // 110xxxxx 10xxxxxx
      d &= 0b0001_1111;
      mixin(appendSixBits);
    }
    else if ((d & 0b1111_0000) == 0b1110_0000)
    { // 1110xxxx 10xxxxxx 10xxxxxx
      d &= 0b0000_1111;
      mixin(appendSixBits ~
            checkNextByte ~ appendSixBits);
    }
    else if ((d & 0b1111_1000) == 0b1111_0000)
    { // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
      d &= 0b0000_0111;
      mixin(appendSixBits ~
            checkNextByte ~ appendSixBits ~
            checkNextByte ~ appendSixBits);
    }
    else
      // 5 and 6 byte UTF-8 sequences are not allowed yet.
      // 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
      // 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
      goto Lerr;

    assert(isTrailByte(*p));

    if (!isValidChar(d))
    {
    Lerr:
      // Three cases:
      // *) the UTF-8 sequence was successfully decoded but the resulting
      //    character is invalid.
      //    p points to last trail byte in the sequence.
      // *) the UTF-8 sequence is overlong.
      //    p points to second byte in the sequence.
      // *) the UTF-8 sequence has more than 4 bytes or starts with
      //    a trail byte.
      //    p points to second byte in the sequence.
      assert(isTrailByte(*p));
      // Move to next ASCII character or lead byte of a UTF-8 sequence.
      while (p < (end-1) && isTrailByte(*p))
        ++p;
      --p;
      assert(!isTrailByte(p[1]));
    Lerr2:
      d = REPLACEMENT_CHAR;
      error(this.p, MID.InvalidUTF8Sequence);
    }

    this.p = p;
    return d;
  }

  static void encodeUTF8(ref char[] str, dchar d)
  {
    assert(!isascii(d), "check for ASCII char before calling encodeUTF8().");
    assert(isValidChar(d), "check if character is valid before calling encodeUTF8().");

    char[6] b = void;
    if (d < 0x800)
    {
      b[0] = 0xC0 | (d >> 6);
      b[1] = 0x80 | (d & 0x3F);
      str ~= b[0..2];
    }
    else if (d < 0x10000)
    {
      b[0] = 0xE0 | (d >> 12);
      b[1] = 0x80 | ((d >> 6) & 0x3F);
      b[2] = 0x80 | (d & 0x3F);
      str ~= b[0..3];
    }
    else if (d < 0x200000)
    {
      b[0] = 0xF0 | (d >> 18);
      b[1] = 0x80 | ((d >> 12) & 0x3F);
      b[2] = 0x80 | ((d >> 6) & 0x3F);
      b[3] = 0x80 | (d & 0x3F);
      str ~= b[0..4];
    }
    /+ // There are no 5 and 6 byte UTF-8 sequences yet.
    else if (d < 0x4000000)
    {
      b[0] = 0xF8 | (d >> 24);
      b[1] = 0x80 | ((d >> 18) & 0x3F);
      b[2] = 0x80 | ((d >> 12) & 0x3F);
      b[3] = 0x80 | ((d >> 6) & 0x3F);
      b[4] = 0x80 | (d & 0x3F);
      str ~= b[0..5];
    }
    else if (d < 0x80000000)
    {
      b[0] = 0xFC | (d >> 30);
      b[1] = 0x80 | ((d >> 24) & 0x3F);
      b[2] = 0x80 | ((d >> 18) & 0x3F);
      b[3] = 0x80 | ((d >> 12) & 0x3F);
      b[4] = 0x80 | ((d >> 6) & 0x3F);
      b[5] = 0x80 | (d & 0x3F);
      str ~= b[0..6];
    }
    +/
    else
     assert(0);
  }
}

unittest
{
  Stdout("Testing Lexer.\n");
  struct Pair
  {
    char[] tokenText;
    TOK type;
  }
  static Pair[] pairs = [
    {"#!äöüß",  TOK.Shebang},       {"\n",      TOK.Newline},
    {"//çay",   TOK.Comment},       {"\n",      TOK.Newline},
                                    {"&",       TOK.AndBinary},
    {"/*çağ*/", TOK.Comment},       {"&&",      TOK.AndLogical},
    {"/+çak+/", TOK.Comment},       {"&=",      TOK.AndAssign},
    {">",       TOK.Greater},       {"+",       TOK.Plus},
    {">=",      TOK.GreaterEqual},  {"++",      TOK.PlusPlus},
    {">>",      TOK.RShift},        {"+=",      TOK.PlusAssign},
    {">>=",     TOK.RShiftAssign},  {"-",       TOK.Minus},
    {">>>",     TOK.URShift},       {"--",      TOK.MinusMinus},
    {">>>=",    TOK.URShiftAssign}, {"-=",      TOK.MinusAssign},
    {"<",       TOK.Less},          {"=",       TOK.Assign},
    {"<=",      TOK.LessEqual},     {"==",      TOK.Equal},
    {"<>",      TOK.LorG},          {"~",       TOK.Tilde},
    {"<>=",     TOK.LorEorG},       {"~=",      TOK.CatAssign},
    {"<<",      TOK.LShift},        {"*",       TOK.Mul},
    {"<<=",     TOK.LShiftAssign},  {"*=",      TOK.MulAssign},
    {"!",       TOK.Not},           {"/",       TOK.Div},
    {"!=",      TOK.NotEqual},      {"/=",      TOK.DivAssign},
    {"!<",      TOK.UorGorE},       {"^",       TOK.Xor},
    {"!>",      TOK.UorLorE},       {"^=",      TOK.XorAssign},
    {"!<=",     TOK.UorG},          {"%",       TOK.Mod},
    {"!>=",     TOK.UorL},          {"%=",      TOK.ModAssign},
    {"!<>",     TOK.UorE},          {"(",       TOK.LParen},
    {"!<>=",    TOK.Unordered},     {")",       TOK.RParen},
    {".",       TOK.Dot},           {"[",       TOK.LBracket},
    {"..",      TOK.Slice},         {"]",       TOK.RBracket},
    {"...",     TOK.Ellipses},      {"{",       TOK.LBrace},
    {"|",       TOK.OrBinary},      {"}",       TOK.RBrace},
    {"||",      TOK.OrLogical},     {":",       TOK.Colon},
    {"|=",      TOK.OrAssign},      {";",       TOK.Semicolon},
    {"?",       TOK.Question},      {",",       TOK.Comma},
    {"$",       TOK.Dollar},        {"cam",     TOK.Identifier},
    {"çay",     TOK.Identifier},    {".0",      TOK.Float64},
    {"0",       TOK.Int32},         {"\n",      TOK.Newline},
    {"\r",      TOK.Newline},       {"\r\n",    TOK.Newline},
    {"\u2028",  TOK.Newline},       {"\u2029",  TOK.Newline}
  ];

  char[] src;

  // Join all token texts into a single string.
  foreach (i, pair; pairs)
    if (pair.type == TOK.Comment && pair.tokenText[1] == '/' || // Line comment.
        pair.type == TOK.Shebang)
    {
      assert(pairs[i+1].type == TOK.Newline); // Must be followed by a newline.
      src ~= pair.tokenText;
    }
    else
      src ~= pair.tokenText ~ " ";

  auto lx = new Lexer(src, "");
  auto token = lx.getTokens();

  uint i;
  assert(token == lx.head);
  assert(token.next.type == TOK.Newline);
  token = token.next.next;
  do
  {
    assert(i < pairs.length);
    assert(token.srcText == pairs[i].tokenText, Format("Scanned '{0}' but expected '{1}'", token.srcText, pairs[i].tokenText));
    ++i;
    token = token.next;
  } while (token.type != TOK.EOF)
}

unittest
{
  Stdout("Testing method Lexer.peek()\n");
  string sourceText = "unittest { }";
  auto lx = new Lexer(sourceText, null);

  auto next = lx.head;
  lx.peek(next);
  assert(next.type == TOK.Newline);
  lx.peek(next);
  assert(next.type == TOK.Unittest);
  lx.peek(next);
  assert(next.type == TOK.LBrace);
  lx.peek(next);
  assert(next.type == TOK.RBrace);
  lx.peek(next);
  assert(next.type == TOK.EOF);

  lx = new Lexer("", null);
  next = lx.head;
  lx.peek(next);
  assert(next.type == TOK.Newline);
  lx.peek(next);
  assert(next.type == TOK.EOF);
}

unittest
{
  // Numbers unittest
  // 0L 0ULi 0_L 0_UL 0x0U 0x0p2 0_Fi 0_e2 0_F 0_i
  // 0u 0U 0uL 0UL 0L 0LU 0Lu
  // 0Li 0f 0F 0fi 0Fi 0i
  // 0b_1_LU 0b1000u
  // 0x232Lu
}

/// ASCII character properties table.
static const int ptable[256] = [
 0, 0, 0, 0, 0, 0, 0, 0, 0,32, 0,32,32, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
32, 0, 0x2200, 0, 0, 0, 0, 0x2700, 0, 0, 0, 0, 0, 0, 0, 0,
 7, 7, 7, 7, 7, 7, 7, 7, 6, 6, 0, 0, 0, 0, 0, 0x3f00,
 0,12,12,12,12,12,12, 8, 8, 8, 8, 8, 8, 8, 8, 8,
 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 0, 0x5c00, 0, 0,16,
 0, 0x70c, 0x80c,12,12,12, 0xc0c, 8, 8, 8, 8, 8, 8, 8, 0xa08, 8,
 8, 8, 0xd08, 8, 0x908, 8, 0xb08, 8, 8, 8, 8, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
];

enum CProperty
{
       Octal = 1,
       Digit = 1<<1,
         Hex = 1<<2,
       Alpha = 1<<3,
  Underscore = 1<<4,
  Whitespace = 1<<5
}

const uint EVMask = 0xFF00; // Bit mask for escape value

private alias CProperty CP;
int isoctal(char c) { return ptable[c] & CP.Octal; }
int isdigit(char c) { return ptable[c] & CP.Digit; }
int ishexad(char c) { return ptable[c] & CP.Hex; }
int isalpha(char c) { return ptable[c] & CP.Alpha; }
int isalnum(char c) { return ptable[c] & (CP.Alpha | CP.Digit); }
int isidbeg(char c) { return ptable[c] & (CP.Alpha | CP.Underscore); }
int isident(char c) { return ptable[c] & (CP.Alpha | CP.Underscore | CP.Digit); }
int isspace(char c) { return ptable[c] & CP.Whitespace; }
int char2ev(char c) { return ptable[c] >> 8; /*(ptable[c] & EVMask) >> 8;*/ }
int isascii(uint c) { return c < 128; }

version(gen_ptable)
static this()
{
  alias ptable p;
  assert(p.length == 256);
  // Initialize character properties table.
  for (int i; i < p.length; ++i)
  {
    p[i] = 0; // Reset
    if ('0' <= i && i <= '7')
      p[i] |= CP.Octal;
    if ('0' <= i && i <= '9')
      p[i] |= CP.Digit;
    if (isdigit(i) || 'a' <= i && i <= 'f' || 'A' <= i && i <= 'F')
      p[i] |= CP.Hex;
    if ('a' <= i && i <= 'z' || 'A' <= i && i <= 'Z')
      p[i] |= CP.Alpha;
    if (i == '_')
      p[i] |= CP.Underscore;
    if (i == ' ' || i == '\t' || i == '\v' || i == '\f')
      p[i] |= CP.Whitespace;
  }
  // Store escape sequence values in second byte.
  assert(CProperty.max <= ubyte.max, "character property flags and escape value byte overlap.");
  p['\''] |= 39 << 8;
  p['"'] |= 34 << 8;
  p['?'] |= 63 << 8;
  p['\\'] |= 92 << 8;
  p['a'] |= 7 << 8;
  p['b'] |= 8 << 8;
  p['f'] |= 12 << 8;
  p['n'] |= 10 << 8;
  p['r'] |= 13 << 8;
  p['t'] |= 9 << 8;
  p['v'] |= 11 << 8;
  // Print a formatted array literal.
  char[] array = "[\n";
  foreach (i, c; ptable)
  {
    array ~= Format((c>255?" 0x{0:x},":"{0,2},"), c) ~ (((i+1) % 16) ? "":"\n");
  }
  array[$-2..$] = "\n]";
  Stdout(array).newline;
}