structure Absyn = 
struct

type pos = int   and   symbol = Symbol.symbol

datatype var = SimpleVar of symbol * pos
            | FieldVar of var * symbol * pos
            | SubscriptVar of var * exp * pos

and exp = VarExp of var
        | NilExp
        | IntExp of int
        | StringExp of string * pos
        | CallExp of {func: symbol, args: exp list, pos: pos}
        | OpExp of {left: exp, oper: oper, right: exp, pos: pos}
        | RecordExp of {fields: (symbol * exp * pos) list,
			typ: symbol, pos: pos}
        | SeqExp of (exp * pos) list
        | AssignExp of {var: var, exp: exp, pos: pos}
        | IfExp of {test: exp, then': exp, else': exp option, pos: pos}
        | WhileExp of {test: exp, body: exp, pos: pos}
	| ForExp of {var: symbol, escape: bool ref,
		     lo: exp, hi: exp, body: exp, pos: pos}
        | BreakExp of pos
        | LetExp of {decs: dec list, body: exp, pos: pos}
        | ArrayExp of {typ: symbol, size: exp, init: exp, pos: pos}

and dec = FunctionDec of fundec list
        | VarDec of {name: symbol,
		     escape: bool ref,
		     typ: (symbol * pos) option,
		     init: exp,
		     pos: pos}
        | TypeDec of {name: symbol, ty: ty, pos: pos} list

and ty = NameTy of symbol * pos
       | RecordTy of field list
       | ArrayTy of symbol * pos

and oper = PlusOp | MinusOp | TimesOp | DivideOp
         | EqOp | NeqOp | LtOp | LeOp | GtOp | GeOp

withtype field = {name: symbol, escape: bool ref, 
		  typ: symbol, pos: pos}
   and   fundec = {name: symbol,
		   params: field list,
		   result: (symbol * pos) option,
		   body: exp,
		   pos: pos}

fun rewriteForExp {var, escape, lo, hi, body, pos} =
    LetExp{
	decs = [VarDec {
		     name = var,
		     escape = escape,
		     typ = SOME(Symbol.symbol("int"), pos),
		     init = lo, pos = pos},
		VarDec {
		    name = Symbol.symbol("_limit"),
		    escape = ref(false),
		    typ = SOME(Symbol.symbol("int"), pos),
		    init = hi, pos = pos}],
	body = WhileExp {
	    test = OpExp {
		left = VarExp(SimpleVar(Symbol.symbol("_limit"), pos)),
		oper = GeOp,
		right = VarExp(SimpleVar(var, pos)),
		pos = pos
	    },
	    body = SeqExp[(body, pos), (AssignExp{
			      var = SimpleVar(var, pos),
			      exp = OpExp{
				  left = VarExp(SimpleVar(var, pos)),
				  oper = PlusOp,
				  right = IntExp(1),
				  pos = pos
			      },
			      pos = pos}, pos)],
	    pos = pos
	},
	pos = pos
    }
    
     
end

structure A = Absyn
        
