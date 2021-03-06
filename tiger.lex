type pos = int

type svalue = Tokens.svalue
type ('a, 'b) token = ('a, 'b) Tokens.token
type lexresult = (svalue, pos) token

val lineNum = ErrorMsg.lineNum
val linePos = ErrorMsg.linePos
fun err (p1,p2) = ErrorMsg.error p1
val nestedComment = ref 0

fun parseInt (ns, p, k) =
  case Int.fromString (ns) of
     SOME n => (Tokens.INT (n, p, p+(String.size ns)))
   | NONE   => (ErrorMsg.error p ("failed to parse integer " ^ ns)
		;k())

fun parseString s = (String.implode o (List.filter (fn x => x <> #"\"")) o String.explode) s

fun changeNestedComment oper = nestedComment := oper(!nestedComment, 1)

fun increaseNestedComment() = changeNestedComment op+

fun decreaseNestedComment() = changeNestedComment op-

fun getNestedCommentLevel() = !nestedComment

fun eof () = let
                val pos = hd(!linePos)
             in
  (print "end of file \n";if getNestedCommentLevel() > 0 then ErrorMsg.error pos "Unescaped comment" else ();
                Tokens.EOF(pos,pos))
             end

%%
  %s COMMENT;
  %header (functor TigerLexFun(structure Tokens: Tiger_TOKENS));
%%
<INITIAL>while => (Tokens.WHILE(yypos, yypos + size yytext));
<INITIAL>for => (Tokens.FOR(yypos, yypos + size yytext));
<INITIAL>to => (Tokens.TO(yypos, yypos + size yytext));
<INITIAL>break => (Tokens.BREAK(yypos, yypos + size yytext));
<INITIAL>let => (Tokens.LET(yypos, yypos + size yytext));
<INITIAL>in => (Tokens.IN(yypos, yypos + size yytext));
<INITIAL>end => (Tokens.END(yypos, yypos + size yytext));
<INITIAL>function => (Tokens.FUNCTION(yypos, yypos + size yytext));
<INITIAL>var => (Tokens.VAR(yypos, yypos + size yytext));
<INITIAL>type => (Tokens.TYPE(yypos, yypos + size yytext));
<INITIAL>array => (Tokens.ARRAY(yypos, yypos + size yytext));
<INITIAL>if => (Tokens.IF(yypos, yypos + size yytext));
<INITIAL>then => (Tokens.THEN(yypos, yypos + size yytext));
<INITIAL>else => (Tokens.ELSE(yypos, yypos + size yytext));
<INITIAL>do => (Tokens.DO(yypos, yypos + size yytext));
<INITIAL>of => (Tokens.OF(yypos, yypos + size yytext));
<INITIAL>nil => (Tokens.NIL(yypos, yypos + size yytext));
<INITIAL>"," => (Tokens.COMMA(yypos, yypos + 1));
<INITIAL>":" => (Tokens.COLON(yypos, yypos + 1));
<INITIAL>";" => (Tokens.SEMICOLON(yypos, yypos + 1));
<INITIAL>"(" => (Tokens.LPAREN(yypos, yypos + 1));
<INITIAL>")" => (Tokens.RPAREN(yypos, yypos + 1));
<INITIAL>"[" => (Tokens.LBRACK(yypos, yypos + 1));
<INITIAL>"]" => (Tokens.RBRACK(yypos, yypos + 1));
<INITIAL>"{" => (Tokens.LBRACE(yypos, yypos + 1));
<INITIAL>"}" => (Tokens.RBRACE(yypos, yypos + 1));
<INITIAL>"." => (Tokens.DOT(yypos, yypos + 1));
<INITIAL>"+" => (Tokens.PLUS(yypos, yypos + 1));
<INITIAL>"-" => (Tokens.MINUS(yypos, yypos + 1));
<INITIAL>"*" => (Tokens.TIMES(yypos, yypos + 1));
<INITIAL>"/" => (Tokens.DIVIDE(yypos, yypos + 1));
<INITIAL>"=" => (Tokens.EQ(yypos, yypos + 1));
<INITIAL>"<>" => (Tokens.NEQ(yypos, yypos + 1));
<INITIAL>"<" => (Tokens.LT(yypos, yypos + 1));
<INITIAL>"<=" => (Tokens.LE(yypos, yypos + 1));
<INITIAL>">" => (Tokens.GT(yypos, yypos + 1));
<INITIAL>">=" => (Tokens.GE(yypos, yypos + 1));
<INITIAL>"&" => (Tokens.AND(yypos, yypos + 1));
<INITIAL>"|" => (Tokens.OR(yypos, yypos + 1));
<INITIAL>":=" => (Tokens.ASSIGN(yypos, yypos + 1));

<INITIAL>[\ \t]*       => (continue());
<INITIAL>\n	=> (lineNum := !lineNum+1; linePos := yypos :: !linePos; continue());

<INITIAL>[a-zA-Z][a-zA-Z0-9_]* => (Tokens.ID(yytext, yypos, yypos + size yytext));
<INITIAL>[0-9]+ => (parseInt(yytext, yypos, continue));
<INITIAL>\"([^\"]*)\" => (Tokens.STRING(parseString(yytext), yypos, yypos + size yytext));
<INITIAL>"/*"  	=> (YYBEGIN COMMENT; increaseNestedComment(); continue());
<COMMENT>"/*"   => (increaseNestedComment(); continue());
<COMMENT> .     => (continue());
<COMMENT>"*/"   => (decreaseNestedComment();
		    if getNestedCommentLevel() = 0 then YYBEGIN INITIAL else ();
		    continue());

.       => (ErrorMsg.error yypos ("illegal character " ^ yytext); continue());

