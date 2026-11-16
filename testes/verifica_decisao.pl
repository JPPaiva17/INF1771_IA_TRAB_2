% Verifica, sem jogar, que a decisão do agente não lê o mapa real.
%
% Percorre o código a partir de executa_acao/1, seguindo cada predicado chamado
% (inclusive dentro de findall/forall/aggregate_all/lambdas), e acusa qualquer
% caminho que chegue a um predicado proibido: tile/3, adjacentes/1, observacoes/1
% e os auxiliares que os usam (adjacente/2, observacao_adj/2, observacao_loc/2).
%
% Uso: swipl -g verifica_decisao -t halt main.pl testes/verifica_decisao.pl
% Também é carregado por testes/executa_testes.py.

proibido(tile/3).
proibido(adjacentes/1).
proibido(observacoes/1).
proibido(adjacente/2).
proibido(observacao_adj/2).
proibido(observacao_loc/2).

%usos_proibidos(-Caminhos): lista de caminhos executa_acao -> ... -> proibido
usos_proibidos(Caminhos) :-
	findall(Caminho, alcanca_proibido(executa_acao/1, Caminho), C0),
	sort(C0, Caminhos).

verifica_decisao :-
	usos_proibidos(C),
	findall(P, (proibido(P)), Ps),
	( C == [] ->
		format("OK: executa_acao/1 não alcança nenhum de ~w~n", [Ps])
	; format("ERRO: a decisão alcança predicados que leem o mapa real:~n"),
	  forall(member(Cam, C), (atomic_list_concat_pi(Cam, Txt), format("   ~w~n", [Txt]))),
	  halt(1) ).

atomic_list_concat_pi(Cam, Txt) :-
	maplist([N/A, S]>>format(atom(S), "~w/~w", [N, A]), Cam, Ss),
	atomic_list_concat(Ss, ' -> ', Txt).

% busca em profundidade no grafo de chamadas, sem repetir predicados
alcanca_proibido(Inicio, Caminho) :-
	nb_setval(vistos, []),
	alcanca(Inicio, [Inicio], Caminho).

alcanca(PI, Rev, Caminho) :-
	( proibido(PI) -> reverse(Rev, Caminho)
	; nb_getval(vistos, V), \+ memberchk(PI, V),
	  nb_setval(vistos, [PI|V]),
	  chamadas(PI, Chamados),
	  member(Q, Chamados),
	  alcanca(Q, [Q|Rev], Caminho) ).

% chamadas(+Nome/Aridade, -Lista): predicados chamados nas cláusulas de um predicado do usuário
chamadas(N/A, Lista) :-
	functor(Cabeca, N, A),
	( predicate_property(user:Cabeca, defined),
	  \+ predicate_property(user:Cabeca, imported_from(_)),
	  \+ predicate_property(user:Cabeca, built_in) ->
		findall(Q, ( catch(clause(user:Cabeca, Corpo), _, fail), objetivo_em(Corpo, Q) ), L0),
		sort(L0, Lista)
	; Lista = [] ).

% objetivo_em(+Corpo, -PI): cada predicado chamado num corpo (entra em construções de
% controle e nos argumentos-meta de predicados de biblioteca, como findall/3)
objetivo_em(G, _) :- var(G), !, fail.
objetivo_em(_:G, PI) :- !, objetivo_em(G, PI).
objetivo_em((A,B), PI) :- !, ( objetivo_em(A, PI) ; objetivo_em(B, PI) ).
objetivo_em((A;B), PI) :- !, ( objetivo_em(A, PI) ; objetivo_em(B, PI) ).
objetivo_em((A->B), PI) :- !, ( objetivo_em(A, PI) ; objetivo_em(B, PI) ).
objetivo_em((A*->B), PI) :- !, ( objetivo_em(A, PI) ; objetivo_em(B, PI) ).
objetivo_em(\+ A, PI) :- !, objetivo_em(A, PI).
objetivo_em(_>>Corpo, PI) :- !, objetivo_em(Corpo, PI).
objetivo_em(G, PI) :-
	callable(G), functor(G, N, A),
	( PI = N/A
	; predicate_property(user:G, meta_predicate(Spec)),
	  arg(I, Spec, M), integer(M),
	  arg(I, G, Meta),
	  meta_objetivo(Meta, M, PI) ).

% argumento-meta: um objetivo (M = 0) ou uma closure que recebe M argumentos extras
meta_objetivo(Meta, _, _) :- var(Meta), !, fail.
meta_objetivo(_>>Corpo, _, PI) :- !, objetivo_em(Corpo, PI).
meta_objetivo(Meta, 0, PI) :- !, objetivo_em(Meta, PI).
meta_objetivo(Meta, M, PI) :- callable(Meta),
	Meta =.. L0, length(Extra, M), append(L0, Extra, L), G =.. L,
	objetivo_em(G, PI).
