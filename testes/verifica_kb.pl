% Verificação da base de conhecimento contra o mapa real (SÓ PARA TESTE).
% Joga partidas com ações aleatórias e, a cada passo, confere se tudo que o
% agente marcou como certo bate com o mapa real (tile/3).
%
% Uso: swipl main.pl testes/verifica_kb.pl            (todos os mapas, 200 partidas)
%      swipl main.pl testes/verifica_kb.pl -- 50       (50 partidas por mapa)

:- initialization(main, main).

mapas(['mapa-facil.pl', 'mapa-medio.pl', 'mapa-dificil.pl']).

main :-
	current_prolog_flag(argv, Args),
	( Args = [A|_], atom_number(A, N) -> true ; N = 200 ),
	mapas(Ms),
	forall(member(M, Ms), verifica_mapa(M, N)),
	( nb_current(total_erros, E), E > 0 -> halt(1) ; halt(0) ).

verifica_mapa(Mapa, N) :-
	nb_setval(erros, 0), nb_setval(seguras, 0), nb_setval(confirmados, 0),
	forall(between(1, N, _), (carrega_mapa(Mapa), joga(300))),
	nb_getval(erros, E), nb_getval(seguras, S), nb_getval(confirmados, C),
	( nb_current(total_erros, T0) -> true ; T0 = 0 ), T is T0 + E, nb_setval(total_erros, T),
	format("~w: ~d partidas, ~d erros; ~d marcações de segura e ~d de perigo conferidas~n", [Mapa, N, E, S, C]).

joga(0) :- !.
joga(_) :- jogo_encerrado(_), !.
joga(K) :-
	random_member(A, [andar, andar, andar, virar_direita, virar_esquerda, pegar]),
	( executa(A) -> true ; true ),
	confere,
	K1 is K - 1, joga(K1).

perigo_real(X, Y) :- tile(X, Y, T), member(T, ['P', 'T', 'D', d]).
tag_real(X, Y, brisa) :- tile(X, Y, 'P').
tag_real(X, Y, palmas) :- tile(X, Y, 'T').
tag_real(X, Y, passos) :- tile(X, Y, 'D').
tag_real(X, Y, passos) :- tile(X, Y, d).

% toda casa marcada como certa e sem perigo precisa ser realmente sem perigo;
% toda casa marcada como certa com um perigo precisa ter exatamente aquele perigo
confere :-
	forall(( certeza(X, Y), memory(X, Y, L) ), confere_casa(X, Y, L)),
	forall(segura(X, Y), ( perigo_real(X, Y) -> erro(X, Y, segura, 'segura/2 errado') ; true )),
	forall(fronteira(X, Y), ( perigo_real(X, Y) -> erro(X, Y, fronteira, 'fronteira/2 errado') ; true )),
	forall(perigo_confirmado(X, Y, P), ( sinal(P, S), tag_real(X, Y, S) -> true ; erro(X, Y, P, 'perigo_confirmado/3 errado') )).

confere_casa(X, Y, L) :-
	exclude([T]>>member(T, [brilho, reflexo]), L, Perigos),
	( Perigos == [] ->
		conta(seguras),
		( perigo_real(X, Y) -> erro(X, Y, L, 'marcada segura, mas tem perigo') ; true )
	; Perigos = [Tag] ->
		conta(confirmados),
		( tag_real(X, Y, Tag) -> true ; erro(X, Y, L, 'perigo confirmado errado') )
	; true ).

conta(C) :- nb_getval(C, V), V1 is V + 1, nb_setval(C, V1).

erro(X, Y, L, Msg) :-
	conta(erros),
	nb_getval(erros, E),
	( E =< 3 -> tile(X, Y, T), format("   ERRO (~w,~w) memoria=~w real='~w': ~w~n", [X, Y, L, T, Msg]) ; true ).
