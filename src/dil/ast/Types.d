/// Author: Aziz Köksal
/// License: GPL3
/// $(Maturity average)
module dil.ast.Types;

public import dil.ast.Type;
import dil.ast.Node,
       dil.ast.Expression,
       dil.ast.Parameters,
       dil.ast.NodeCopier,
       dil.ast.Meta;
import dil.lexer.Identifier;
import dil.semantic.Types;
import dil.Enums;
import common;

/// Syntax error.
class IllegalType : TypeNode
{
  mixin(memberInfo());
  this()
  {
    mixin(set_kind);
  }
  mixin methods;
}

/// $(BNF IntegralType := char | int | float | ...)
class IntegralType : TypeNode
{
  TOK tok;
  mixin(memberInfo("tok"));
  this(TOK tok)
  {
    mixin(set_kind);
    this.tok = tok;
  }
  mixin methods;
}

/// $(BNF ModuleScopeType := ".")
class ModuleScopeType : TypeNode
{
  mixin(memberInfo());
  this()
  {
    mixin(set_kind);
  }
  mixin methods;
}

/// $(BNF IdentifierType := Type? Identifier)
class IdentifierType : TypeNode
{
  Token* name;
  mixin(memberInfo("next?", "name"));
  this(TypeNode next, Token* name)
  {
    super(next);
    mixin(set_kind);
    this.name = name;
  }

  @property Identifier* id()
  {
    return name.ident;
  }

  mixin methods;
}

/// $(BNF TypeofType := typeof "(" (Expression | return) ")")
class TypeofType : TypeNode
{
  Expression expr;

  mixin(memberInfo("expr?"));
  this(Expression e)
  {
    mixin(set_kind);
    addOptChild(e);
    this.expr = e;
  }

  /// Returns true for typeof "(" return ")".
  bool isTypeofReturn()
  {
    return expr is null;
  }

  mixin methods;
}

/// $(BNF TemplateInstanceType :=
////  Identifier "!" (TemplateArgumentList | TemplateArgumentSingle))
class TmplInstanceType : TypeNode
{
  Token* name;
  TemplateArguments targs;
  mixin(memberInfo("next?", "name", "targs"));
  this(TypeNode next, Token* name, TemplateArguments targs)
  {
    super(next);
    mixin(set_kind);
    addOptChild(targs);
    this.name = name;
    this.targs = targs;
  }

  @property Identifier* id()
  {
    return name.ident;
  }

  mixin methods;
}

/// $(BNF PointerType:= Type "*")
class PointerType : TypeNode
{
  mixin(memberInfo("next"));
  this(TypeNode next)
  {
    super(next);
    mixin(set_kind);
  }
  mixin methods;
}

/// $(BNF
////ArrayType := DynamicArray | StaticArray | SliceArray | AssociativeArray
////DynamicArray     := T "[" "]"
////StaticArray      := T "[" E "]"
////SliceArray       := T "[" E ".." E "]" # for slicing tuples
////AssociativeArray := T "[" T "]"
////)
class ArrayType : TypeNode
{
  Expression index1, index2;
  TypeNode assocType;

  mixin(memberInfo("next", "index1?", "index2?", "assocType?"));
  /// DynamicArray.
  this(TypeNode next)
  {
    super(next);
    mixin(set_kind);
  }

  /// StaticArray or SliceArray.
  this(TypeNode next, Expression e1, Expression e2 = null)
  {
    this(next);
    addChild(e1);
    addOptChild(e2);
    this.index1 = e1;
    this.index2 = e2;
  }

  /// AssociativeArray.
  this(TypeNode next, TypeNode assocType)
  {
    this(next);
    addChild(assocType);
    this.assocType = assocType;
  }

  /// For ASTSerializer.
  this(TypeNode next, Expression e1, Expression e2, TypeNode assocType)
  {
    if (e1)
      this(next, e1, e2);
    else if (assocType)
      this(next, assocType);
    else
      this(next);
  }

  bool isDynamic()
  {
    return assocType is null && index1 is null;
  }

  bool isStatic()
  {
    return index1 !is null && index2 is null;
  }

  bool isSlice()
  {
    return index1 !is null && index2 !is null;
  }

  bool isAssociative()
  {
    return assocType !is null;
  }

  mixin methods;
}

/// $(BNF FunctionType := ReturnType function ParameterList)
class FunctionType : TypeNode
{
  alias returnType = next;
  Parameters params;
  mixin(memberInfo("returnType", "params"));
  this(TypeNode returnType, Parameters params)
  {
    super(returnType);
    mixin(set_kind);
    addChild(params);
    this.params = params;
  }
  mixin methods;
}

/// $(BNF DelegateType := ReturnType delegate ParameterList)
class DelegateType : TypeNode
{
  alias returnType = next;
  Parameters params;
  mixin(memberInfo("returnType", "params"));
  this(TypeNode returnType, Parameters params)
  {
    super(returnType);
    mixin(set_kind);
    addChild(params);
    this.params = params;
  }
  mixin methods;
}

/// $(BNF BaseClassType := Protection? BasicType)
class BaseClassType : TypeNode
{
  Protection prot;
  mixin(memberInfo("prot", "next"));
  this(Protection prot, TypeNode type)
  {
    super(type);
    mixin(set_kind);
    this.prot = prot;
  }
  mixin methods;
}

/// $(BNF ModifierType := ModAttrType | ModParenType
////ModAttrType := Modifier Type
////ModParenType := Modifier "(" Type ")"
////Modifier := const | immutable | shared | inout)
class ModifierType : TypeNode
{
  Token* mod;
  bool hasParen; // True if, e.g.: const "(" Type ")"
  mixin(memberInfo("next?", "mod", "hasParen"));

  this(TypeNode next, Token* mod, bool hasParen)
  {
    super(next);
    mixin(set_kind);
    this.mod = mod;
    this.hasParen = hasParen;
  }

  this(Token* mod)
  {
    this(null, mod, false);
  }

  bool isImmutable() @property
  {
    return mod.kind == TOK.Immutable;
  }

  bool isConst() @property
  {
    return mod.kind == TOK.Const;
  }

  bool isShared() @property
  {
    return mod.kind == TOK.Shared;
  }

  bool isInout() @property
  {
    return mod.kind == TOK.Inout;
  }

  mixin methods;
}
