Nonterminals
  plural_form
  expr if_expr plural_expr bool_expr
  bool_op comp_op.

Terminals
  nplurals plural n int
  '==' '!=' '>' '<' '>=' '<=' '=' '?' ':' '%' '||' '&&' ';' '(' ')'.

Rootsymbol plural_form.
Endsymbol '$end'.

Right 100 if_expr.
Left 200 bool_op.
Nonassoc 300 comp_op.
Right 400 '%'.

plural_form ->
    nplurals '=' int ';' plural '=' plural_expr ';' : {value('$3'), '$7'}.

plural_expr -> int : value('$1').
plural_expr -> bool_expr : '$1'.
plural_expr -> if_expr : '$1'.

bool_expr -> expr comp_op expr : {'$2', '$1', '$3'}.
bool_expr -> bool_expr bool_op bool_expr : {'$2', '$1', '$3'}.
bool_expr -> '(' bool_expr ')' : {paren, '$2'}.

if_expr -> bool_expr '?' expr ':' expr : {'if', '$1', '$3', '$5'}.
if_expr -> '(' if_expr ')' : {paren, '$2'}.

expr -> expr '%' expr : {'%', '$1', '$3'}.
expr -> int : value('$1').
expr -> if_expr : '$1'.
expr -> n : n.
expr -> '(' expr ')' : '$2'.

comp_op -> '!=' : operator('$1').
comp_op -> '>' : operator('$1').
comp_op -> '==' : operator('$1').
comp_op -> '<' : operator('$1').
comp_op -> '>=' : operator('$1').
comp_op -> '<=' : operator('$1').

bool_op -> '&&' : operator('$1').
bool_op -> '||' : operator('$1').

Erlang code.

value({int, _Line, Int}) -> Int.

operator({Op, _Line}) -> Op.
