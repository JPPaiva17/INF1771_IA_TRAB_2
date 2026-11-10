% Testes unitários (plunit). Uso: swipl main.pl testes/testes_unitarios.pl
:- use_module(library(plunit)).
:- initialization((run_tests -> halt(0) ; halt(1)), main).

anda(L) :- forall(member(A, L), executa(A)).
coloca(X, Y, D) :- retract(posicao(_,_,_)), assert(posicao(X, Y, D)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Fase 1: mapas e controle de partida
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
:- begin_tests(fase1).

test(mapa_padrao) :-
	carrega_mapa('mapa.pl'), map_size(12,12), aggregate_all(count, tile(_,_,_), 144).
test(troca_mapa) :-
	carrega_mapa('mapa-facil'), aggregate_all(count, tile(_,_,'P'), 5),
	carrega_mapa('mapa_dificil.pl'), aggregate_all(count, tile(_,_,'P'), 8),
	aggregate_all(count, tile(_,_,_), 144).
test(parede_falha_sem_contar) :-
	carrega_mapa('mapa.pl'), executa(virar_esquerda), \+ executa(andar), acoes_executadas(1).
test(acao_conta_pontua) :-
	carrega_mapa('mapa.pl'), executa(virar_direita), acoes_executadas(1), pontuacao(-1).
test(ouro_conta) :-
	carrega_mapa('mapa.pl'), coloca(1,11,norte), executa(andar), brilho_aqui,
	executa(pegar), ouros_coletados(1), pontuacao(494),
	executa(pegar), ouros_coletados(1).
test(reinicia_devolve_ouro) :-
	carrega_mapa('mapa.pl'), coloca(1,11,norte), anda([andar, pegar]),
	reinicia_jogo, tile(1,12,'O'), ouros_coletados(0), acoes_executadas(0), pontuacao(0).
test(sair_so_na_origem) :-
	carrega_mapa('mapa.pl'), coloca(2,1,norte), \+ executa(sair),
	coloca(1,1,norte), executa(sair), jogo_encerrado(saiu), \+ executa(andar).
test(parar) :-
	carrega_mapa('mapa.pl'), executa(parar), jogo_encerrado(parou).
test(morte_no_poco) :-
	carrega_mapa('mapa.pl'), anda([andar, andar]), jogo_encerrado(morreu), pontuacao(-1002),
	resultado('mapa.pl', -1002, 0, nao, 2, morreu).

:- end_tests(fase1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Fase 2: base de conhecimento e inferência
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
:- begin_tests(fase2).

% sem percepção na origem: vizinhas seguras e na fronteira; a origem é segura e visitada
test(sem_percepcao_vizinhas_seguras) :-
	carrega_mapa('testes/mapa_teste_poco.pl'),
	percepcao(1,1,[]), segura(1,1), visitada(1,1),
	segura(1,2), segura(2,1), fronteira(1,2), fronteira(2,1), \+ fronteira(1,1),
	desconhecida(3,3), \+ segura(3,3).

% brisa com duas candidatas: nada é provado (a regra original errava neste tipo de caso)
test(duas_candidatas_nao_conclui) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), executa(andar),
	percepcao(1,2,[brisa]),
	perigo_possivel(1,3,poco), perigo_possivel(2,2,poco),
	\+ perigo_confirmado(_,_,_), \+ segura(2,2), \+ certeza(1,3).

% a casa (2,1) exclui (2,2); a brisa sentida antes em (1,2) passa a ter uma só candidata,
% mesmo com o agente longe dela (reavaliação do mapa inteiro)
test(candidata_unica_global) :-
	carrega_mapa('testes/mapa_teste_poco.pl'),
	anda([andar, virar_direita, virar_direita, andar, virar_esquerda, andar]),
	posicao(2,1,_),
	segura(2,2), perigo_confirmado(1,3,poco), certeza(1,3), memory(1,3,[brisa]),
	\+ perigo_possivel(1,3,_).

% inimigo provado em (2,3) exclui poço ali; então o poço sentido em (2,2) só pode estar em (3,2)
test(cadeia_de_exclusao) :-
	carrega_mapa('testes/mapa_teste_cadeia.pl'),
	anda([andar, andar]),
	percepcao(1,3,[passos]), perigo_confirmado(2,3,inimigo),
	\+ perigo_confirmado(3,2,_),
	anda([virar_direita, virar_direita, andar, virar_esquerda, andar]),
	posicao(2,2,_), percepcao(2,2,[brisa, passos]),
	perigo_confirmado(3,2,poco), \+ perigo_possivel(3,2,inimigo),
	energia(100).

% entrar no teletransportador: a casa vira perigo provado, não é visitada nem fronteira,
% e o agente conhece a casa onde "acordou"
test(teleporte_marcado, [nondet, forall(between(1, 20, _))]) :-
	carrega_mapa('testes/mapa_teste_teleporte.pl'),
	anda([virar_direita, andar]),
	perigo_confirmado(2,1,teleporte), pisou(2,1), \+ visitado(2,1),
	\+ segura(2,1), \+ fronteira(2,1),
	once((posicao(X,Y,_), pisou(X,Y), memory(X,Y,_), percepcao(X,Y,_))).

% casa onde o agente esteve e sofreu ataque: perigo provado, não é segura
test(inimigo_pisado) :-
	carrega_mapa('testes/mapa_teste_cadeia.pl'),
	anda([andar, andar, virar_direita, andar]),
	posicao(2,3,_), energia(E), E < 100,
	perigo_confirmado(2,3,inimigo), \+ segura(2,3).

% reiniciar apaga a base de conhecimento
test(reinicia_apaga_kb) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), anda([andar]),
	reinicia_jogo, \+ percepcao(1,2,_), \+ pisou(1,2), \+ perigo_confirmado(_,_,_).

:- end_tests(fase2).
