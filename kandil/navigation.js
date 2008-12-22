/// Author: Aziz Köksal

/// Execute when document is ready.
$(function() {
  $("#panels").prepend(new QuickSearch("apiqs", "#apilist", quickSearchSymbols).input)
              .prepend(new QuickSearch("modqs", "#modlist", quickSearchSymbols).input);

  $("#modqs").hide(); // Initially hidden.

  var symbols = $(".symbol");
  // Add code display functionality to symbol links.
  symbols.click(function(event) {
    event.preventDefault();
    showCode($(this));
  })

  var header = symbols[0];
  symbols = symbols.slice(1);

  var itemlist = {}
  itemlist.root = new SymbolItem(header.textContent, "module", header.textContent);
  itemlist[''] = itemlist.root; // The empty string has to point to the root.
  function insertIntoList()
  {
    [parentFQN, name] = rpartition(this.name, '.')
    var sym = new SymbolItem(this.textContent, $(this).attr("kind"), this.name);
    itemlist[parentFQN].sub.push(sym);
    itemlist[sym.fqn] = sym;
    // TODO: add D attribute information.
  }
  symbols.each(insertIntoList);

  $("#apilist").append(createSymbolsUL(itemlist.root.sub));

//   $("#apilist > ul").treeview({
//     animated: "fast",
//     collapsed: true
//   })

  function makeCurrentTab() {
    $("span.current", this.parentNode).removeClass('current');
    $(this).addClass('current');
  }

  // Assign click event handlers for the tabs.
  $("#apitab").click(makeCurrentTab)
              .click(function() {
    var container = $("#panels");
    $("> *:visible", container).hide();
    $("#apilist", container).show(); // Display the API list.
    $("#apiqs").show(); // Show the filter text box.
  })
  $("#modtab").click(makeCurrentTab)
              .click(function() {
    var container = $("#panels");
    $("> *:visible", container).hide();
    var list = $("#modlist:has(ul)", container);
    if (!list.length) {
      list = createModulesList();
      container.append(list.hide()); // Append hidden.
    }
    list.show(); // Display the modules list.
    $("#modqs").show(); // Show the filter text box.
  })
})

/// Constructs a QuickSearch object.
function QuickSearch(id, symlist, callback)
{
  this.input = $("<input id='"+id+"' class='filterbox'"+
                 " type='text' value='Filter...'/>");
  this.input.callback = callback;
  this.input.timeoutId = 0; // Initialize the id.
  function delayCallback(input)
  {
    clearTimeout(input.timeoutId);
    input.timeoutId = setTimeout(function() {
      input.cancelSearch = false;
      callback(input, $(symlist)[0]);
    }, 500);
  }
  this.input.keyup(function(e) {
    switch (e.keyCode) {
    case 0:case 9:case 13:case 16:case 17:case 18:case 37:case 39:case 224:
      break; // Ignore meta keys and other keys.
    case 27: // Escape key.
      clearTimeout(this.timeoutId);
      this.cancelSearch = true;
      break;
    default:
      delayCallback(this);
    }
  })
  function clearInput(e) {
    $(this).val("").unbind("mousedown", clearInput);
  }
  this.input.mousedown(clearInput)
  return this;
}

function quickSearchSymbols(input, symlist)
{
  var str = input.value;
  // Strip leading and trailing whitespace.
  str = str.replace(/^\s+/, "").replace(/\s+$/, "");

  // Select all descending list items.
  var items = symlist.getElementsByTagName("li");
  // Reset classes.
  for (i in items)
    items[i].className = "";

  if (str.length == 0) {
    $(symlist).removeClass("filtered");
    return; // Nothing to do if query is empty.
  }

  // Parse the query.
  var words = str.toLowerCase().split(/\s+/);
  // var attributes = [];
  // for (i in words)
  //   if (words[i][0] == ':')
  //     attributes = words[i];

  // Iterate over the list in reverse.
  // TODO: test forward iteration.
  for (var i = items.length-1; i >= 0; i--)
  {
    if (input.cancelSearch)
      return;
    var match = false;
    var item = items[i];
    var parent_li = item.parentNode.parentNode;
    // childNodes[1] is the <a/> tag or the text node (package names).
    var text = item.childNodes[1].textContent.toLowerCase();
    for (j in words)
      if (text.search(words[j]) != -1)
      {
        match = true;
        item.className = "match";
        parent_li.className = "parent_of_match";
        break;
      }
    // Propagate the class upward the tree.
    if (!match && item.className == "parent_of_match")
      parent_li.className = "parent_of_match";
  }
  symlist.className = "filtered";
}

/// A tree item for symbols.
function SymbolItem(name, kind, fqn)
{
  this.name = name; /// The text to be displayed.
  this.kind = kind; /// The kind of this symbol.
  this.fqn = fqn; /// The fully qualified name.
  this.sub = []; /// Sub-symbols.
  return this;
}

/// Returns an image tag for the provided kind of symbol.
function getPNGIcon(kind)
{
  var functionSet = {
    "function":1,"unittest":1,"invariant":1,"new":1,"delete":1,
    "invariant":1,"sctor":1,"sdtor":1,"ctor":1,"dtor":1,
  };
  // Other kinds: (they have their own PNG icons)
  // "variable","enummem","alias","typedef","class",
  // "interface","struct","union","template"
  if (functionSet[kind])
    kind = "function";
  return "<img src='img/icon_"+kind+".png' width='16' height='16'/>";
}

function addDAttributes()
{
  $("#apilist li").each(function() {
    // TODO:
  })
}

/// Constructs a ul (enclosing nested ul's) from the symbols data structure.
function createSymbolsUL(symbols)
{
  var list = "<ul>";
  for (i in symbols)
  {
    var sym = symbols[i];
    [fqn, count] = rpartition(sym.fqn, ':');
    count = fqn ? "<sub>"+count+"</sub>" : ""; // An index.
    list += "<li kind='"+sym.kind+"'>"+getPNGIcon(sym.kind)+
            "<a href='#"+sym.fqn+"'>"+sym.name+count+"</a>";
    if (sym.sub && sym.sub.length)
      list += createSymbolsUL(sym.sub);
    list += "</li>";
  }
  return list + "</ul>";
}

/// Constructs a ul (enclosing nested ul's) from g_moduleObjects.
function createModulesUL(symbols)
{
  var list = "<ul>";
  for (i in symbols)
  {
    var sym = symbols[i];
    list += "<li kind='"+sym.kind+"'>"+getPNGIcon(sym.kind);
    if (sym.sub && sym.sub.length)
      list += sym.name + createModulesUL(sym.sub);
    else
      list += "<a href='"+sym.fqn+".html'>"+sym.name+"</a>"
    list += "</li>";
  }
  return list + "</ul>";
}

/// Creates an unordered list from the global modules list and appends
/// it to the modlist panel.
function createModulesList()
{
  return $("#modlist").append(createModulesUL(g_moduleObjects));
}

/// An array of all the lines of this module's source code.
var g_sourceCode = [];

/// Extracts the code from the HTML file and sets g_sourceCode.
function setSourceCode(html_code)
{
  html_code = html_code.split(/<pre class="sourcecode">|<\/pre>/);
  if (html_code.length == 3)
  { // Get the code between the pre tags.
    var code = html_code[1];
    // Split on newline.
    g_sourceCode = code.split(/\n|\r\n?|\u2028|\u2029/);
  }
}

/// Returns the relative URL to the source code of this module.
function getSourceCodeURL()
{
  return "./htmlsrc/" + g_moduleFQN + ".html";
}

/// Shows the code for a symbol in a div tag beneath it.
function showCode(symbol)
{
  var dt_tag = symbol.parent()[0];
  var line_beg = parseInt(symbol.attr("beg"));
  var line_end = parseInt(symbol.attr("end"));

  if (dt_tag.code_div)
  { // Remove the displayed code div.
    dt_tag.code_div.remove();
    delete dt_tag.code_div;
    return;
  }

  function show()
  { // The function that actually displays the code.
    if ($(dt_tag).is("h1")) { // Special case.
      line_beg = 1;
      line_end = g_sourceCode.length -2;
    }
    // Get the code lines.
    var code = g_sourceCode.slice(line_beg, line_end+1);
    code = code.join("\n");
    // Create the lines column.
    var lines = "";
    for (var i = line_beg; i <= line_end; i++)
      lines += '<a href="'+getSourceCodeURL()+'#L'+i+'">' + i + '</a>\n';
    lines = '<pre class="lines_column">'+lines+'</pre>';
    // Create the code block.
    var block = '<pre class="d_code">'+code+'</pre>';
    var table = $('<table/>').append('<tr><td class="lines">'+lines+'</td><td>'+block+'</td></tr>');
    // Create a container div.
    var div = $('<div class="loaded_code"/>');
    div.append(table);
    $(dt_tag).after(div);
    // Store the created div.
    dt_tag.code_div = div;
  }

  var showCodeHandler;

  if (g_sourceCode.length == 0)
  { // Load the HTML source code file.
    var doc_url = getSourceCodeURL();

    function errorHandler(request, error, exception)
    {
      var msg = $("<p class='ajaxerror'>Failed loading code from '"+doc_url+"'.</p>");
      $(dt_tag).after(msg);
      setTimeout(function(){msg.fadeOut(400, function(){$(this).remove()})}, 4000);
    }

    try {
      $.ajax({url: doc_url, dataType: "text", error: errorHandler,
        success: function(data) {
          setSourceCode(data);
          show();
        }
      });
    }
    catch(e){ errorHandler(); }
  }
  else // Already loaded. Show the code.
    show();
}

function reportBug()
{
  // TODO: implement.
}

/// Splits a string returning a tuple (head, tail).
function rpartition(str, sep)
{
  var sep_pos = str.lastIndexOf(sep);
  var head = (sep_pos == -1) ? "" : str.slice(0, sep_pos);
  var tail = str.slice(sep_pos+1);
  return [head, tail];
}
