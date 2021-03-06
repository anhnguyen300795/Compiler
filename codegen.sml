signature CODEGEN = 
sig
  structure Frame : FRAME
  val codegen : Frame.frame -> Tree.stm -> Assem.instr list
  val removeRedundantMoves: Assem.instr list * Frame.register Temp.Table.table -> Assem.instr list
end

structure Mipsgen: CODEGEN =
struct

structure Frame = MipsFrame
structure A = Assem
structure T = Tree

fun getAssemRelOp T.EQ = "beq"
  | getAssemRelOp T.NE = "bne"
  | getAssemRelOp T.LT = "blt"
  | getAssemRelOp T.GT = "bgt"
  | getAssemRelOp T.LE = "ble"
  | getAssemRelOp T.GE = "bge"
  | getAssemRelOp _ = "Not supported"

fun getOperStm T.PLUS = "add"
  | getOperStm T.MINUS = "sub"
  | getOperStm T.MUL = "mul"
  | getOperStm T.DIV = "div"
  | getOperStm _ = "Oper not used"
    
fun codegen (frame) (stm: T.stm): A.instr list =
    let
	val ilist = ref (nil: A.instr list)
	fun emit (x: A.instr) = (ilist := x :: !ilist)
	fun result (gen: Temp.temp -> A.instr): Temp.temp =
	    let val t = Temp.newtemp() in
		(emit (gen t); t) end

	val toStr = fn x => if x >= 0 then Int.toString(x) else "-"^Int.toString(~x)
	(* Helper functions *)
	fun genStoreStm (offset: int, d: T.exp, s: T.exp) =
	    (*Assume that there is no other op except PLUS right after T.MEM according to translate*)
	    (* in sw s0, (x)s1, both s0 and s1 is in USE set, so defSet = []*) 
	    emit(A.OPER{assem = "sw `s0, " ^ toStr(offset) ^ "(`s1)\n",
			     src = [munchExp(s), munchExp(d)],
			     dst = [],
			     jump = NONE})

	and genLwStm (offset:int, d: Temp.temp, s: T.exp) =
	    (*Assume that there is no other op except PLUS right after T.MEM according to translate*)
	    emit(A.OPER{assem = "lw `d0, " ^ toStr(offset) ^ "(`s0)\n",
			src = [munchExp s],
			dst = [d],
			jump = NONE})

	and genLwExp (offset:int, s: T.exp) =
	    (*Assume that there is no other op except PLUS right after T.MEM according to translate*)
	    result(fn d => A.OPER{assem = "lw `d0, " ^ toStr(offset) ^ "(`s0)\n",
				  src = [munchExp s],
				  dst = [d],
				  jump = NONE})

	and munchStm (T.SEQ(a,b)) = (munchStm a; munchStm b)
	  | munchStm (T.LABEL l) = emit(A.LABEL{assem = S.name(l) ^ ":\n", lab = l})
	  | munchStm (T.JUMP(T.NAME(l), ls)) = emit(A.OPER {assem = "j "^S.name l^"\n", src =[],
							    dst = [], jump = SOME ls})
	  | munchStm (T.JUMP(e, ls)) = emit(A.OPER {assem = "jr `j0\n", src =[munchExp e],
						    dst = [], jump = SOME ls})

	  | munchStm (T.CJUMP (relop, l, r, t, f)) =
	    let
		val oper = getAssemRelOp relop
	    in
		emit(A.OPER {assem = oper ^ " `s0,`s1,`j0\n",
			     src =[munchExp(l), munchExp(r)],
			     dst = [], jump = SOME [t] })
	    end
	  (* Save e2 to Mem e1 => "sw s0, offset(s1)" *)
	  | munchStm (T.MOVE(T.MEM(T.BINOP(_, e1, T.CONST i)), e2)) =
	    genStoreStm(i, e1, e2)
	  | munchStm (T.MOVE(T.MEM(T.BINOP(_, T.CONST i, e1)), e2)) =
	    genStoreStm(i, e1, e2)
	  | munchStm (T.MOVE(T.MEM(e1), e2)) =
	    genStoreStm(0, e1, e2)

	  | munchStm (T.MOVE(T.TEMP(r), T.CONST(i))) =
	    emit (A.OPER {assem = "li `d0, " ^ toStr(i) ^ "\n",
			  src = [],
			  dst = [r],
			  jump = NONE})

	  | munchStm (T.MOVE(T.TEMP(d), T.TEMP(s))) =
	    emit (A.MOVE {assem = "move `d0, `s0\n",
			  src = s,
			  dst = d})

	  | munchStm (T.MOVE(T.TEMP(d), T.MEM(T.BINOP(_, s, T.CONST i)))) =
	    genLwStm(i, d, s)
	  | munchStm (T.MOVE(T.TEMP(d), T.MEM(T.BINOP(_, T.CONST i, s)))) =
	    genLwStm(i, d, s)
	  | munchStm (T.MOVE(T.TEMP(d), T.MEM(s))) =
	    genLwStm(0, d, s)
          | munchStm(T.MOVE(T.TEMP(d), T.NAME(lab))) = 
            emit(A.OPER {assem="la `d0, " ^ (Symbol.name lab) ^ "\n",
                         src=[], dst=[d], jump=NONE})
	  | munchStm (T.MOVE(T.TEMP(r), e)) = (* munchExp e => T.TEMP(x)*)
	    emit (A.OPER {assem = "move `d0, `s0\n",
			  src = [munchExp e],
			  dst = [r],
			  jump = NONE})
	  | munchStm(T.MOVE(e1, e2)) = ()
	  | munchStm (T.EXP e) = (munchExp e; ())

	and munchExp(T.BINOP(T.PLUS, e, T.CONST(i))): Temp.temp =
	    result(fn d => A.OPER{assem = "addi `d0,`s0," ^ toStr(i) ^ "\n",
			src = [munchExp e],
			dst = [d],
			jump = NONE})
	  | munchExp(T.BINOP(T.PLUS, T.CONST(i), e)) =
	    result(fn d => A.OPER{assem = "addi `d0,`s0," ^ toStr(i) ^ "\n",
			src = [munchExp e],
			dst = [d],
			jump = NONE})

	  | munchExp(T.BINOP(T.MINUS, e, T.CONST i)) =
            result(fn d => A.OPER {assem="addi `d0, `s0, " ^ toStr (~i) ^ "\n",
				   src=[munchExp e], dst=[d], jump=NONE})
	  (*AND, OR, SHIFT, ... does not exist in front-end, see tiger.grm*)
	  | munchExp (T.BINOP(oper, e1, e2)) =
	    result(fn d => A.OPER{assem = getOperStm(oper)^" `d0,`s0,`s1\n",
			src = [munchExp(e1), munchExp(e2)],
			dst = [d],
			jump = NONE})

	  | munchExp (T.MEM(T.BINOP(_, e, T.CONST(i)))) = genLwExp (i, e)
	  | munchExp (T.MEM(T.BINOP(_, T.CONST(i), e))) = genLwExp (i, e)
	  | munchExp (T.MEM(e)) = genLwExp (0, e)
	  | munchExp (T.TEMP t) = t
	  | munchExp (T.ESEQ(s, e)) = (munchStm(s); munchExp(e))
	  | munchExp (T.NAME l) =
	    result(fn d => A.OPER{assem= "la `d0, " ^ S.name(l) ^ "\n",
                                  src=[], dst=[d], jump=NONE})
	  | munchExp (T.CONST i) =
	    result(fn d => A.OPER{assem = "li `d0, " ^ toStr(i) ^ "\n",
				  src = [], dst = [d], jump = NONE})
	  | munchExp (T.CALL(T.NAME(f), args)) =
	    let
		fun restoreRegs (regPairs) = map (fn x => munchStm(T.MOVE x)) regPairs
		fun saveRegs (argRegs: Temp.temp list, allocDst: (int -> T.exp)): (T.exp * T.exp) list =
		      let
			  fun f (i, reg) =
			      let
				  val src = T.TEMP(reg)
				  val dst = allocDst i
			      in
				  munchStm(T.MOVE(dst, src));
				  (src, dst)
			      end
		      in
			  List.mapi f argRegs 
		      end

		fun saveArgRegs i =
		    (*i+1 because we save from top to bottom => tosave
		     at position fp + 1 => $fp + 4 has to be used*)
		    T.MEM(T.BINOP(T.PLUS, T.TEMP(F.FP), T.CONST((i+1) * F.wordSize)))
					 
		val saveToFrame = true
		fun saveCallerRegs _ = F.exp (F.allocLocal frame saveToFrame) (Tr.TEMP F.FP)

		val argRegPair = saveRegs(F.argRegs, saveArgRegs)
		val callerRegPair = saveRegs(F.callersaveRegs, saveCallerRegs)
	    in
		emit(A.OPER{assem = "jal " ^ S.name(f) ^"\n",
			     src = munchArgs(args),
			     dst = F.RA::F.RV::F.callersaveRegs , jump = NONE});
		restoreRegs(callerRegPair);
		restoreRegs(argRegPair);
		F.RV
	    end
		
		

	  and munchArgs (args: T.exp list): Temp.temp list =
	      let
		  val argRegs = map (fn (x: Temp.temp, _) => x) F.argregs
		  fun moveArgToTemp (arg, r) = munchStm(T.MOVE(T.TEMP(r), T.TEMP(munchExp(arg))))
		  fun moveArgToFrame (arg, offset) =
		      munchStm(T.MOVE(T.MEM(T.BINOP(T.PLUS, T.TEMP(F.SP), T.CONST offset)), T.TEMP(munchExp(arg))))

		  val START_POS_IN_FRAME_ARG = 16
		  fun helper (i, arg::tl, offset) =
		      if i > 3
		      then (moveArgToFrame(arg, offset); helper(i+1, tl, offset + F.wordSize))
		      else
			  let
			      val temp = List.nth(argRegs, i)
			  in
			      moveArgToTemp(arg, temp);
			      temp::helper(i+1, tl, offset)
			  end
		    | helper (_, [], _) = []
	      in
		  helper(0, args, START_POS_IN_FRAME_ARG)
	      end
								
    in
	munchStm stm;
	rev (!ilist)
    end


fun removeRedundantMoves (instrs: A.instr list, alloc: Frame.register Temp.Table.table): A.instr list =
    let
	fun getColor t =
	    case Temp.Table.look(alloc, t) of
		SOME x => x
	      | NONE => raise Fail ("No allocation found for " ^ Temp.makestring(t))
			      
	fun f (A.MOVE{dst, src, ...}) = false andalso getColor(dst) <> getColor(src)
	  | f _ = true
    in
	List.filter f instrs
    end
    
end
    
