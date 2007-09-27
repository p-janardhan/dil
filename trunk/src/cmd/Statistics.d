/++
  Author: Aziz Köksal
  License: GPL3
+/
module cmd.Statistics;
import dil.Token;
import dil.File;
import dil.Lexer;
import common;

struct Statistics
{
  uint whitespaceCount;
  uint wsTokenCount;
  uint keywordCount;
  uint identCount;
  uint numberCount;
  uint commentCount;
  uint linesOfCode;

  void opAddAssign(Statistics s)
  {
    this.whitespaceCount += s.whitespaceCount;
    this.wsTokenCount    += s.wsTokenCount;
    this.keywordCount    += s.keywordCount;
    this.identCount      += s.identCount;
    this.numberCount     += s.numberCount;
    this.commentCount    += s.commentCount;
    this.linesOfCode     += s.linesOfCode;
  }
}

void execute(string[] filePaths)
{
  Statistics[] stats;
  foreach (filePath; filePaths)
    stats ~= getStatistics(filePath);

  Statistics total;

  foreach (i, ref stat; stats)
  {
    total += stat;
    Stdout.formatln(
      "----\n"
      "File: {0}\n"
      "Whitespace character count: {1}\n"
      "Whitespace token count: {2}\n"
      "Keyword count: {3}\n"
      "Identifier count: {4}\n"
      "Number count: {5}\n"
      "Comment count: {6}\n"
      "Lines of code: {7}",
      filePaths[i],
      stat.whitespaceCount,
      stat.wsTokenCount,
      stat.keywordCount,
      stat.identCount,
      stat.numberCount,
      stat.commentCount,
      stat.linesOfCode
    );
  }

  if (filePaths.length > 1)
    Stdout.formatln(
      "--------------------------------------------------------------------------------\n"
      "Total:\n"
      "Whitespace character count: {0}\n"
      "Whitespace token count: {1}\n"
      "Keyword count: {2}\n"
      "Identifier count: {3}\n"
      "Number count: {4}\n"
      "Comment count: {5}\n"
      "Lines of code: {6}",
      total.whitespaceCount,
      total.wsTokenCount,
      total.keywordCount,
      total.identCount,
      total.numberCount,
      total.commentCount,
      total.linesOfCode
    );
}

Statistics getStatistics(string filePath)
{
  auto sourceText = loadFile(filePath);
  auto lx = new Lexer(sourceText, filePath);

  auto token = lx.getTokens();

  Statistics stats;

  stats.linesOfCode = lx.loc;
  // Traverse linked list.
  while (token.type != TOK.EOF)
  {
    token = token.next;

    // Count whitespace characters
    if (token.ws !is null)
      stats.whitespaceCount += countWhitespaceCharacters(token.ws, token.start);

    switch (token.type)
    {
    case TOK.Identifier:
      stats.identCount++;
      break;
    case TOK.Comment:
      stats.commentCount++;
      break;
    case TOK.Int32, TOK.Int64, TOK.Uint32, TOK.Uint64,
         TOK.Float32, TOK.Float64, TOK.Float80,
         TOK.Imaginary32, TOK.Imaginary64, TOK.Imaginary80:
      stats.numberCount++;
      break;
    default:
      if (token.isKeyword)
        stats.keywordCount++;
    }

    if (token.isWhitespace)
      stats.wsTokenCount++;
  }
  return stats;
}

/// Counts newlines, \t, \v, \f and ' ' as whitespace characters.
uint countWhitespaceCharacters(char* p, char* end)
{
  uint count;
Loop:
  while (1)
  {
    switch (*p)
    {
    case '\r':
      if (p[1] == '\n')
        ++p;
    case '\n':
      ++p;
      ++count;
      break;
    case LS[0]:
      if (p[1] == LS[1] && (p[2] == LS[2] || p[2] == PS[2]))
      {
        p += 3;
        ++count;
        break;
      }
    default:
      if (!dil.Lexer.isspace(*p))
        break Loop; // Exit loop.
      ++p;
      ++count;
    }
  }
  assert(p is end);
  return count;
}