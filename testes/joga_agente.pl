% Joga partidas completas com a política executa_acao/1 e resume os resultados.
% O mapa real (tile/3) é usado aqui SÓ para conferir: se o agente pisou num perigo,
% a casa tinha de ser uma das que ele escolheu arriscar (não podia estar marcada segura).
%
% Uso: swipl main.pl testes/joga_agente.pl              (30 partidas por mapa)
%      swipl main.pl testes/joga_agente.pl -- 100       (100 partidas por mapa)
%      swipl main.pl testes/joga_agente.pl -- 100 v     (imprime cada partida)

:- initialization(main, main).

mapas_avaliados(['mapa-facil.pl', 'mapa-medio.pl', 'mapa-dificil.pl']).

main :-
	current_prolog_flag(argv, Args),
	( Args = [A|_], atom_number(A, N) -> true ; N = 30 ),
	( memberchk(v, Args) -> Verboso = sim ; Verboso = nao ),
	mapas_avaliados(Ms),
	nb_setval(violacoes, 0),
	format("~w~t~16|~w~t~28|~w~t~38|~w~t~50|~w~t~60|~w~n",
	       [mapa, 'pontuação', ouros, 'vivo %', 'ações', 'motivos']),
	forall(member(M, Ms), avalia_mapa(M, N, Verboso)),
	nb_getval(violacoes, V),
	( V > 0 -> format("~d violações (pisou em perigo numa casa marcada segura)~n", [V]), halt(1)
	; halt(0) ).

avalia_mapa(Mapa, N, Verboso) :-
	findall(r(P, O, S, A, Mot), ( between(1, N, _), partida(Mapa, Verboso, P, O, S, A, Mot) ), Rs),
	media([P]>>member(r(P,_,_,_,_), Rs), MP),
	media([O]>>member(r(_,O,_,_,_), Rs), MO),
	media([A]>>member(r(_,_,_,A,_), Rs), MA),
	aggregate_all(count, member(r(_,_,sim,_,_), Rs), Vivos), PV is 100 * Vivos / N,
	findall(Mot, member(r(_,_,_,_,Mot), Rs), Mots), msort(Mots, MS), clumped(MS, Cont),
	format("~w~t~16|~1f~t~28|~2f~t~38|~0f~t~50|~1f~t~60|~w~n", [Mapa, MP, MO, PV, MA, Cont]).

media(Gerador, M) :- findall(X, call(Gerador, X), Xs), sum_list(Xs, S), length(Xs, L), M is S / L.

partida(Mapa, Verboso, P, O, S, A, Mot) :-
	carrega_mapa(Mapa),
	joga(3000),
	resultado(_, P, O, S, A, Mot),
	( Verboso == sim -> format("  ~w: pontos=~w ouros=~w vivo=~w acoes=~w fim=~w~n", [Mapa, P, O, S, A, Mot]) ; true ).

joga(0) :- !.
joga(_) :- jogo_encerrado(_), !.
joga(K) :-
	( executa_acao(Acao) -> true ; Acao = nenhuma ),
	confere_passo(Acao),
	( Acao \== nenhuma, executa(Acao) -> true ; true ),
	K1 is K - 1, joga(K1).

% antes de andar: se a casa à frente tem perigo real, ela não pode estar marcada como segura
confere_passo(andar) :- posicao(X, Y, D), a_frente(X, Y, D, X2, Y2),
	tile(X2, Y2, T), member(T, ['P', 'T', 'D', d]), segura(X2, Y2), !,
	nb_getval(violacoes, V), V1 is V + 1, nb_setval(violacoes, V1),
	format("   VIOLAÇÃO: andou para (~w,~w) = '~w' marcada segura~n", [X2, Y2, T]).
confere_passo(_).
