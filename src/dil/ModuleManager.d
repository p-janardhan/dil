/// Author: Aziz Köksal
/// License: GPL3
/// $(Maturity high)
module dil.ModuleManager;

import dil.semantic.Module,
       dil.semantic.Package,
       dil.semantic.Symbol;
import dil.lexer.Token;
import dil.i18n.Messages;
import dil.Compilation,
       dil.Diagnostics,
       dil.String;
import util.Path;
import common;

import std.algorithm : sort;
import std.range : assumeSorted;

/// Manages loaded modules in various tables.
class ModuleManager
{
  /// The root package. Contains all other modules and packages.
  Package rootPackage;
  /// Maps full package names to packages. E.g.: dil.ast
  Package[hash_t] packageTable;
  /// Maps FQN paths to modules. E.g.: dil/ast/Node
  Module[hash_t] moduleFQNPathTable;
  /// Maps absolute file paths to modules. E.g.: /home/user/dil/src/main.d
  Module[hash_t] absFilePathTable;
  /// Loaded modules in sequential order.
  Module[] loadedModules;
  /// Loaded modules which are ordered according to the number of
  /// import statements in each module (ascending order.)
  Module[] orderedModules;
  /// Provides tables and compiler variables.
  CompilationContext cc;

  /// Constructs a ModuleManager object.
  this(CompilationContext cc)
  {
    this.rootPackage = new Package(null, cc.tables.idents);
    packageTable[0] = this.rootPackage;
    assert(hashOf("") == 0);
    this.cc = cc;
  }

  /// Looks up a module by its file path. E.g.: "src/dil/ModuleManager.d"
  /// Relative paths are made absolute.
  Module moduleByPath(cstring moduleFilePath)
  {
    auto absFilePath = absolutePath(moduleFilePath);
    if (auto existingModule = hashOf(absFilePath) in absFilePathTable)
      return *existingModule;
    return null;
  }

  /// Looks up a module by its f.q.n. path. E.g.: "dil/ModuleManager"
  Module moduleByFQN(cstring moduleFQNPath)
  {
    if (auto existingModule = hashOf(moduleFQNPath) in moduleFQNPathTable)
      return *existingModule;
    return null;
  }

  /// Loads and parses a module given a file path.
  /// Returns: A new Module instance or an existing one from the table.
  Module loadModuleFile(cstring moduleFilePath)
  {
    if (auto existingModule = moduleByPath(moduleFilePath))
      return existingModule;

    if (Path(moduleFilePath).isFolder)
    {
      auto msg = cc.diag.formatMsg(MID.ModulePathIsFolder, moduleFilePath);
      cc.diag ~= new LexerError(new Location(moduleFilePath, 0), msg);
      return null;
    }

    // Create a new module.
    auto newModule = new Module(moduleFilePath, cc);
    newModule.parse();

    addModule(newModule);

    return newModule;
  }

  /// Loads a module given an FQN path. Searches import paths.
  Module loadModule(cstring moduleFQNPath)
  {
    // Look up in table if the module is already loaded.
    if (auto existingModule = moduleByFQN(moduleFQNPath))
      return existingModule;

    // Locate the module in the file system.
    auto moduleFilePath = findModuleFile(moduleFQNPath);
    if (!moduleFilePath.length)
      return null; // No module found.

    // Load the module file.
    auto modul = loadModuleFile(moduleFilePath);
    if (!modul)
      return null;

    auto packageFQN = getPackageFQN(moduleFQNPath);
    if (getPackageFQN(modul.getFQNPath()) != packageFQN)
      // Error: the requested module is not in the correct package.
      error(modul, MID.ModuleNotInPackage, packageFQN);

    return modul;
  }

  /// Inserts the given module into the tables.
  void addModule(Module newModule)
  {
    auto absFilePath = absolutePath(newModule.filePath());

    auto moduleFQNPath = newModule.getFQNPath();
    auto fqnPathHash = hashOf(moduleFQNPath);

    if (auto existingModule = fqnPathHash in moduleFQNPathTable)
      // Error: two module files have the same f.q. module name.
      return error(newModule,
        MID.ConflictingModuleFiles, newModule.filePath());

    // Insert into the tables.
    moduleFQNPathTable[fqnPathHash] = newModule;
    absFilePathTable[hashOf(absFilePath)] = newModule;
    loadedModules ~= newModule;
    newModule.ID = loadedModules.length;
    insertOrdered(newModule);

    auto nrOfPckgs = packageTable.length; // Remember for error checking.
    // Add the module to its package.
    auto pckg = getPackage(newModule.packageName);
    pckg.add(newModule);

    if (auto p = hashOf(newModule.getFQN()) in packageTable)
      // Error: module and package share the same name.
      // Happens when: "src/dil/module.d", "src/dil.d"
      // There's a package dil and a module dil.
      return error(newModule,
        MID.ConflictingModuleAndPackage, newModule.getFQN());

    if (nrOfPckgs != packageTable.length) // Were new packages added?
    { // Check whether any new package is in conflict with an existing module.
      uint i; // Used to get the exact package in a module declaration.
      auto p = newModule.parent.to!(Package);
      for (; p.parent; p = p.parentPackage()) // Go up until root package.
      {
        i++;
        auto pckgFQN = p.getFQN(); // E.g.: dil.ast
        auto pckgFQNPath = pckgFQN.replace('.', dirSep); // E.g.: dil/ast
        if (hashOf(pckgFQNPath) in moduleFQNPathTable)
          // Error: package and module share the same name.
          return error(newModule.moduleDecl.packages[$-i], newModule,
            MID.ConflictingPackageAndModule, pckgFQN);
      }
    }
  }

  /// Compares the number of imports of two modules.
  /// Returns: true if a imports less than b.
  static bool compareImports(Module a, Module b)
  {
    return a.imports.length < b.imports.length;
  }

  /// Insert a module into the ordered list.
  void insertOrdered(Module newModule)
  {
    auto sorted = orderedModules.assumeSorted!compareImports();
    auto i = sorted.lowerBound(newModule).length;
    if (i == orderedModules.length)
      orderedModules ~= newModule;
    else
      orderedModules = orderedModules[0..i] ~ newModule ~ orderedModules[i..$];
  }

  /// Returns the package given a f.q. package name.
  /// Returns the root package for an empty string.
  Package getPackage(cstring pckgFQN)
  {
    auto fqnHash = hashOf(pckgFQN);
    if (auto existingPackage = fqnHash in packageTable)
      return *existingPackage;

    cstring prevFQN, lastPckgName;
    // E.g.: pckgFQN = 'dil.ast', prevFQN = 'dil', lastPckgName = 'ast'
    splitPackageFQN(pckgFQN, prevFQN, lastPckgName);
    // Recursively build package hierarchy.
    auto parentPckg = getPackage(prevFQN); // E.g.: 'dil'

    // Create a new package.
    auto pckg = new Package(lastPckgName, cc.tables.idents); // E.g.: 'ast'
    parentPckg.add(pckg); // 'dil'.add('ast')

    // Insert the package into the table.
    packageTable[fqnHash] = pckg;

    return pckg;
  }

  /// Splits e.g. 'dil.ast.xyz' into 'dil.ast' and 'xyz'.
  /// Params:
  ///   pckgFQN = The full package name to be split.
  ///   prevFQN = Set to 'dil.ast' in the example.
  ///   lastName = The last package name; set to 'xyz' in the example.
  void splitPackageFQN(cstring pckgFQN,
    out cstring prevFQN, out cstring lastName)
  {
    auto s = String(pckgFQN).rpartition('.');
    prevFQN = s[0][];
    lastName = s[1][];
  }

  /// Returns e.g. 'dil.ast' for 'dil/ast/Node'.
  static char[] getPackageFQN(cstring moduleFQNPath)
  {
    return String(moduleFQNPath).sub(dirSep, '.').rpartition('.')[0][];
  }

  /// Searches for a module in the file system looking in importPaths.
  /// Returns: The file path to the module, or null if it wasn't found.
  static cstring findModuleFile(cstring moduleFQNPath, cstring[] importPaths)
  {
    auto filePath = Path();
    foreach (importPath; importPaths)
    { // E.g.: "path/to/src" ~ "/" ~ "dil/ast/Node" ~ ".d"
      (filePath.set(importPath) /= moduleFQNPath) ~= ".d";
      // or: "src/dil/ast/Node.di"
      if (filePath.exists() || (filePath~="i").exists())
        return filePath[];
    }
    return null;
  }

  /// ditto
  cstring findModuleFile(cstring moduleFQNPath)
  {
    return findModuleFile(moduleFQNPath, cc.importPaths);
  }

  /// A predicate for sorting symbols in ascending order.
  /// Compares symbol names ignoring case.
  static bool compareSymbolNames(Symbol a, Symbol b)
  {
    return String(a.name.str).icmp(b.name.str) < 0;
  }

  /// Sorts the the subpackages and submodules of pckg.
  void sortPackageTree(Package pckg)
  {
    pckg.packages.sort!(compareSymbolNames)();
    pckg.modules.sort!(compareSymbolNames)();
    foreach (subpckg; pckg.packages)
      sortPackageTree(subpckg);
  }

  /// Calls sortPackageTree() with this.rootPackage.
  void sortPackageTree()
  {
    sortPackageTree(rootPackage);
  }

  /// Returns a normalized, absolute path.
  static cstring absolutePath(cstring path)
  {
    return Path(path).absolute().normalize()[];
  }

  /// Reports an error.
  void error(Module modul, MID mid, ...)
  {
    auto msg = cc.diag.formatMsg(mid, _arguments, _argptr);
    auto loc = modul.loc.t.getErrorLocation(modul.filePath);
    cc.diag ~= new SemanticError(loc, msg);
  }

  /// Reports an error.
  void error(Token* locTok, Module modul, MID mid, ...)
  {
    auto location = locTok.getErrorLocation(modul.filePath());
    auto msg = cc.diag.formatMsg(mid, _arguments, _argptr);
    cc.diag ~= new SemanticError(location, msg);
  }

  /// Reports the error that the module was not found.
  /// Params:
  ///   modulePath = File path to the module.
  ///   loc = Optional source location (from an import statement.)
  void errorModuleNotFound(cstring modulePath, Location loc = null)
  {
    if(!loc) loc = new Location(modulePath, 0);
    auto msg = cc.diag.formatMsg(MID.CouldntLoadModule, modulePath);
    cc.diag ~= new LexerError(loc, msg);
  }
}
