/++
  Author: Aziz Köksal
  License: GPL3
+/
module dil.Declarations;
import dil.SyntaxTree;
import dil.Expressions;
import dil.Types;
import dil.Statements;
import dil.Token;
import dil.Scope;

abstract class Declaration : Node
{
  bool hasBody;
  this(bool hasBody)
  {
    super(NodeCategory.Declaration);
    this.hasBody = hasBody;
  }

  void semantic(Scope sc)
  {
//     foreach (node; this.children)
//       if (node.category == NodeCategory.Declaration)
//         (cast(Declaration)cast(void*)node).semantic(sc);
  }
}

class Declarations : Declaration
{
  this()
  {
    super(true);
    mixin(set_kind);
  }

  void opCatAssign(Declaration d)
  {
    this.children ~= d;
  }

  void opCatAssign(Declaration[] decls)
  {
    this.children ~= decls;
  }

  void opCatAssign(Declarations ds)
  {
    this.children ~= ds.children;
  }
}

class EmptyDeclaration : Declaration
{
  this()
  {
    super(false);
    mixin(set_kind);
  }
}

class IllegalDeclaration : Declaration
{
  Token* token;
  this(Token* token)
  {
    super(false);
    mixin(set_kind);
    this.token = token;
  }
}

/// FQN = fully qualified name
alias Token*[] ModuleFQN; // Identifier(.Identifier)*

class ModuleDeclaration : Declaration
{
  Token* moduleName;
  Token*[] packages;
  this(ModuleFQN moduleFQN)
  {
    super(false);
    mixin(set_kind);
    assert(moduleFQN.length != 0);
    this.moduleName = moduleFQN[$-1];
    this.packages = moduleFQN[0..$-1];
  }

  char[] getFQN()
  {
    auto pname = getPackageName('.');
    if (pname.length)
      return pname ~ "." ~ getName();
    else
      return getName();
  }

  char[] getName()
  {
    if (moduleName)
      return moduleName.identifier;
    return null;
  }

  char[] getPackageName(char separator)
  {
    char[] pname;
    foreach (pckg; packages)
      if (pckg)
        pname ~= pckg.identifier ~ separator;
    if (pname.length)
      pname = pname[0..$-1]; // Remove last separator
    return pname;
  }
}

class ImportDeclaration : Declaration
{
  ModuleFQN[] moduleFQNs;
  Token*[] moduleAliases;
  Token*[] bindNames;
  Token*[] bindAliases;
  bool isStatic_;

  this(ModuleFQN[] moduleFQNs, Token*[] moduleAliases, Token*[] bindNames, Token*[] bindAliases, bool isStatic)
  {
    super(false);
    mixin(set_kind);
    this.moduleFQNs = moduleFQNs;
    this.moduleAliases = moduleAliases;
    this.bindNames = bindNames;
    this.bindAliases = bindAliases;
    this.isStatic_ = isStatic;
  }

  char[][] getModuleFQNs(char separator)
  {
    char[][] FQNs;
    foreach (moduleFQN; moduleFQNs)
    {
      char[] FQN;
      foreach (ident; moduleFQN)
        if (ident)
          FQN ~= ident.identifier ~ separator;
      FQNs ~= FQN[0..$-1]; // Remove last separator
    }
    return FQNs;
  }

  bool isStatic()
  {
    return isStatic_;
  }

  bool isPublic()
  {
    // TODO:
    return false;
  }
}

class AliasDeclaration : Declaration
{
  Declaration decl;
  this(Declaration decl)
  {
    super(false);
    mixin(set_kind);
    this.children = [decl];
    this.decl = decl;
  }
}

class TypedefDeclaration : Declaration
{
  Declaration decl;
  this(Declaration decl)
  {
    super(false);
    mixin(set_kind);
    this.children = [decl];
    this.decl = decl;
  }
}

class EnumDeclaration : Declaration
{
  Token* name;
  Type baseType;
  EnumMember[] members;
  this(Token* name, Type baseType, EnumMember[] members, bool hasBody)
  {
    super(hasBody);
    mixin(set_kind);
    if (baseType)
      this.children = [baseType];
    if (members.length)
        this.children ~= members;

    this.name = name;
    this.baseType = baseType;
    this.members = members;
  }
}

class EnumMember : Node
{
  Token* name;
  Expression value;
  this(Token* name, Expression value)
  {
    super(NodeCategory.Other);
    mixin(set_kind);
    if (value)
      this.children = [value];

    this.name = name;
    this.value = value;
  }
}

class ClassDeclaration : Declaration
{
  Token* name;
  TemplateParameters tparams;
  BaseClass[] bases;
  Declarations decls;
  this(Token* name, TemplateParameters tparams, BaseClass[] bases, Declarations decls, bool hasBody)
  {
    super(hasBody);
    mixin(set_kind);
    if (tparams)
      this.children = [tparams];
    if (bases.length)
      this.children ~= bases;
    if (decls)
      this.children ~= decls;

    this.name = name;
    this.tparams = tparams;
    this.bases = bases;
    this.decls = decls;
  }
}

class InterfaceDeclaration : Declaration
{
  Token* name;
  TemplateParameters tparams;
  BaseClass[] bases;
  Declarations decls;
  this(Token* name, TemplateParameters tparams, BaseClass[] bases, Declarations decls, bool hasBody)
  {
    super(hasBody);
    mixin(set_kind);
    if (tparams)
      this.children = [tparams];
    if (bases.length)
      this.children ~= bases;
    if (decls)
      this.children ~= decls;

    this.name = name;
    this.tparams = tparams;
    this.bases = bases;
    this.decls = decls;
  }
}

class StructDeclaration : Declaration
{
  Token* name;
  TemplateParameters tparams;
  Declarations decls;
  this(Token* name, TemplateParameters tparams, Declarations decls, bool hasBody)
  {
    super(hasBody);
    mixin(set_kind);
    if (tparams)
      this.children = [tparams];
    if (decls)
      this.children ~= decls;

    this.name = name;
    this.tparams = tparams;
    this.decls = decls;
  }
}

class UnionDeclaration : Declaration
{
  Token* name;
  TemplateParameters tparams;
  Declarations decls;
  this(Token* name, TemplateParameters tparams, Declarations decls, bool hasBody)
  {
    super(hasBody);
    mixin(set_kind);
    if (tparams)
      this.children = [tparams];
    if (decls)
      this.children ~= decls;

    this.name = name;
    this.tparams = tparams;
    this.decls = decls;
  }
}

class ConstructorDeclaration : Declaration
{
  Parameters parameters;
  FunctionBody funcBody;
  this(Parameters parameters, FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    assert(parameters !is null && funcBody !is null);
    this.children = [cast(Node)parameters, funcBody];

    this.parameters = parameters;
    this.funcBody = funcBody;
  }
}

class StaticConstructorDeclaration : Declaration
{
  FunctionBody funcBody;
  this(FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    assert(funcBody !is null);
    this.children = [funcBody];

    this.funcBody = funcBody;
  }
}

class DestructorDeclaration : Declaration
{
  FunctionBody funcBody;
  this(FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    this.children = [funcBody];

    this.funcBody = funcBody;
  }
}

class StaticDestructorDeclaration : Declaration
{
  FunctionBody funcBody;
  this(FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    this.children = [funcBody];

    this.funcBody = funcBody;
  }
}

class FunctionDeclaration : Declaration
{
  Type returnType;
  Token* funcName;
  TemplateParameters tparams;
  Parameters params;
  FunctionBody funcBody;
  this(Type returnType, Token* funcName, TemplateParameters tparams, Parameters params, FunctionBody funcBody)
  {
    assert(returnType !is null);
    super(funcBody.funcBody !is null);
    mixin(set_kind);
    this.children = [returnType];
    if (tparams)
      this.children ~= tparams;
    this.children ~= [cast(Node)params, funcBody];

    this.returnType = returnType;
    this.funcName = funcName;
    this.tparams = tparams;
    this.params = params;
    this.funcBody = funcBody;
  }
}

class VariableDeclaration : Declaration
{
  Type type;
  Token*[] idents;
  Expression[] values;
  this(Type type, Token*[] idents, Expression[] values)
  {
    super(false);
    mixin(set_kind);
    if (type)
      this.children = [type];
    foreach(value; values)
      if (value)
        this.children ~= value;

    this.type = type;
    this.idents = idents;
    this.values = values;
  }
}

class InvariantDeclaration : Declaration
{
  FunctionBody funcBody;
  this(FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    assert(funcBody !is null);
    this.children = [funcBody];

    this.funcBody = funcBody;
  }
}

class UnittestDeclaration : Declaration
{
  FunctionBody funcBody;
  this(FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    assert(funcBody !is null);
    this.children = [funcBody];

    this.funcBody = funcBody;
  }
}

class DebugDeclaration : Declaration
{
  Token* spec;
  Token* cond;
  Declaration decls, elseDecls;

  this(Token* spec, Token* cond, Declaration decls, Declaration elseDecls)
  {
    super(true /+decls.length != 0+/);
    mixin(set_kind);
    if (decls)
      this.children = [decls];
    if (elseDecls)
      this.children ~= elseDecls;

    this.spec = spec;
    this.cond = cond;
    this.decls = decls;
    this.elseDecls = elseDecls;
  }
}

class VersionDeclaration : Declaration
{
  Token* spec;
  Token* cond;
  Declaration decls, elseDecls;

  this(Token* spec, Token* cond, Declaration decls, Declaration elseDecls)
  {
    super(true /+decls.length != 0+/);
    mixin(set_kind);
    if (decls)
      this.children = [decls];
    if (elseDecls)
      this.children ~= elseDecls;

    this.spec = spec;
    this.cond = cond;
    this.decls = decls;
    this.elseDecls = elseDecls;
  }
}

class StaticIfDeclaration : Declaration
{
  Expression condition;
  Declaration ifDecls, elseDecls;
  this(Expression condition, Declaration ifDecls, Declaration elseDecls)
  {
    super(true);
    mixin(set_kind);
    assert(condition !is null);
    this.children = [condition];
    if (ifDecls)
      this.children ~= ifDecls;
    if (elseDecls)
      this.children ~= elseDecls;

    this.condition = condition;
    this.ifDecls = ifDecls;
    this.elseDecls = elseDecls;
  }
}

class StaticAssertDeclaration : Declaration
{
  Expression condition, message;
  this(Expression condition, Expression message)
  {
    super(true);
    mixin(set_kind);
    assert(condition !is null);
    this.children = [condition];
    if (message)
      this.children ~= message;
    this.condition = condition;
    this.message = message;
  }
}

class TemplateDeclaration : Declaration
{
  Token* name;
  TemplateParameters tparams;
  Declarations decls;
  this(Token* name, TemplateParameters tparams, Declarations decls)
  {
    super(true);
    mixin(set_kind);
    if (tparams)
      this.children = [tparams];
    assert(decls !is null);
    this.children ~= decls;

    this.name = name;
    this.tparams = tparams;
    this.decls = decls;
  }
}

class NewDeclaration : Declaration
{
  Parameters parameters;
  FunctionBody funcBody;
  this(Parameters parameters, FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    assert(parameters !is null && funcBody !is null);
    this.children = [cast(Node)parameters, funcBody];

    this.parameters = parameters;
    this.funcBody = funcBody;
  }
}

class DeleteDeclaration : Declaration
{
  Parameters parameters;
  FunctionBody funcBody;
  this(Parameters parameters, FunctionBody funcBody)
  {
    super(true);
    mixin(set_kind);
    assert(parameters !is null && funcBody !is null);
    this.children = [cast(Node)parameters, funcBody];

    this.parameters = parameters;
    this.funcBody = funcBody;
  }
}

class AttributeDeclaration : Declaration
{
  TOK attribute;
  Declaration decls;
  this(TOK attribute, Declaration decls)
  {
    super(true);
    mixin(set_kind);
    assert(decls !is null);
    this.children ~= decls;

    this.attribute = attribute;
    this.decls = decls;
  }
}

class ExternDeclaration : AttributeDeclaration
{
  Linkage linkage;
  this(Linkage linkage, Declaration decls)
  {
    super(TOK.Extern, decls);
    mixin(set_kind);
    if (linkage)
      this.children ~= linkage;
    this.linkage = linkage;
  }
}

class AlignDeclaration : AttributeDeclaration
{
  int size;
  this(int size, Declaration decls)
  {
    super(TOK.Align, decls);
    mixin(set_kind);
    this.size = size;
  }
}

class PragmaDeclaration : AttributeDeclaration
{
  Token* ident;
  Expression[] args;
  this(Token* ident, Expression[] args, Declaration decls)
  {
    if (args.length)
      this.children ~= args; // Add args before calling super().
    super(TOK.Pragma, decls);
    mixin(set_kind);

    this.ident = ident;
    this.args = args;
  }
}

class MixinDeclaration : Declaration
{
  Expression[] templateIdents;
  Token* mixinIdent;
  Expression argument; // mixin ( AssignExpression )
  this(Expression[] templateIdents, Token* mixinIdent)
  {
    super(false);
    mixin(set_kind);
    assert(templateIdents.length != 0);
    this.children = templateIdents;
    this.templateIdents = templateIdents;
    this.mixinIdent = mixinIdent;
  }
  this(Expression argument)
  {
    super(false);
    mixin(set_kind);
    assert(argument !is null);
    this.children = [argument];
    this.argument = argument;
  }
}
