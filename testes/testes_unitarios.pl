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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Fase 3: planejamento de rotas
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% só para teste: o agente "sente" todas as casas sem sair do lugar (conhece o mapa inteiro)
conhece_mapa :-
	posicao(X0,Y0,D0),
	forall(dentro_mapa(X,Y), (coloca(X,Y,D0), registra_percepcao)),
	coloca(X0,Y0,D0), infere.

% aplica as ações a partir de um estado, sem executar no jogo
simula(E, [], E).
simula(E, [A|R], F) :- once(efeito(E, A, E1)), simula(E1, R, F).

passa_por(Acoes, E0, X, Y) :- append(P, _, Acoes), simula(E0, P, e(X,Y,_)), !.

% assert fora da unidade de teste (dentro dela iria para o módulo do plunit)
define_plano(Acoes, E) :- assert(plano(Acoes, E)).

:- begin_tests(fase3).

% caminho direto passaria pelo poço (1,3): a rota contorna por (2,2)
test(rota_desvia_do_poco) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), conhece_mapa, coloca(1,2,norte),
	rota_ate([(2,3)], A),
	A == [virar_direita, andar, virar_esquerda, andar],
	\+ passa_por(A, e(1,2,norte), 1, 3).

% viradas custam como andar: de costas para o alvo são 2 viradas + 1 passo;
% até (3,3) o caminho reto pelo norte cruza o poço (1,3), então são 6 ações pelo leste
test(conta_viradas) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), conhece_mapa,
	coloca(1,1,sul), custo_rota([(1,2)], 3),
	coloca(1,1,norte), custo_rota([(3,1)], 3),
	rota_ate([(3,3)], A), length(A, 6), simula(e(1,1,norte), A, e(3,3,_)),
	\+ passa_por(A, e(1,1,norte), 1, 3).

% o alvo mais próximo (em ações) é o escolhido entre vários
test(alvo_mais_proximo) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), conhece_mapa, coloca(1,1,norte),
	rota_ate([(3,3), (1,2), (3,1)], [andar]).

% não atravessa casas sem informação
test(sem_rota_por_desconhecido) :-
	carrega_mapa('testes/mapa_teste_poco.pl'),
	\+ rota_ate([(3,3)], _).

% a casa-alvo pode ser arriscada, mas o caminho até ela não
test(alvo_arriscado_permitido) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), executa(andar),
	\+ segura(1,3), rota_ate([(1,3)], [andar]),
	\+ rota_ate([(2,3)], _).

% já está no alvo: rota vazia
test(ja_no_alvo) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), rota_ate([(1,1)], []).

% na casa de um inimigo (não segura) o agente ainda consegue girar e sair
test(sai_da_casa_do_inimigo) :-
	carrega_mapa('testes/mapa_teste_cadeia.pl'),
	anda([andar, andar, virar_direita, andar]), posicao(2,3,leste),
	once(rota_ate([(1,1)], A)), simula(e(2,3,leste), A, e(1,1,_)).

% plano executado até o fim: chega ao alvo e o plano some
test(plano_executa_ate_o_fim) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), conhece_mapa,
	planeja([(3,3)]), tem_plano, executa_plano,
	posicao(3,3,_), \+ tem_plano, acoes_executadas(6), pontuacao(-6).

% ação diferente da planejada descarta o plano
test(plano_cancelado_por_desvio) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), conhece_mapa,
	planeja([(3,3)]), executa(pegar), \+ tem_plano.

% agente fora do estado esperado: a próxima ação do plano não é usada
test(plano_cancelado_fora_do_lugar) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), conhece_mapa,
	planeja([(3,3)]), coloca(2,2,sul),
	\+ proxima_acao_plano(_), \+ tem_plano.

% teletransporte no meio do plano descarta o resto
test(plano_cancelado_por_teleporte, [forall(between(1, 10, _))]) :-
	carrega_mapa('testes/mapa_teste_teleporte.pl'),
	define_plano([virar_direita, andar, andar], e(1,1,norte)),
	executa(virar_direita), user:plano([andar, andar], e(1,1,leste)),
	executa(andar), \+ tem_plano.

:- end_tests(fase3).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Fase 4: política de decisão executa_acao/1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% joga com a política até o fim (ou até K ações)
joga_politica(0) :- !.
joga_politica(_) :- jogo_encerrado(_), !.
joga_politica(K) :- executa_acao(A), executa(A), K1 is K - 1, joga_politica(K1).

% o agente pisa em (X,Y) e percebe o que há ali (para montar situações)
pisa(X, Y, D) :- coloca(X, Y, D), set_real(X, Y), atualiza_obs.

define_energia(E) :- retractall(energia(_)), assert(energia(E)).
define_ouros(N) :- retractall(ouros_coletados(_)), assert(ouros_coletados(N)).

% a decisão é determinística: uma única resposta (o Python usa a primeira de todas)
uma_decisao(A) :- findall(X, executa_acao(X), [A]).

:- begin_tests(fase4).

test(pega_ouro) :-
	carrega_mapa('testes/mapa_teste_itens.pl'), pisa(3,1,norte), uma_decisao(pegar).

test(item_so_com_pouca_energia) :-
	carrega_mapa('testes/mapa_teste_itens.pl'), pisa(1,3,norte),
	uma_decisao(A), A \== pegar,
	define_energia(40), uma_decisao(pegar).

test(explora_fronteira_segura) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), uma_decisao(A),
	memberchk(A, [andar, virar_direita]), tem_plano.

% mapa sem ouro: explora tudo o que é seguro, não arrisca o poço 50/50, volta e sai
test(partida_poco_sobrevive_e_sai) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), joga_politica(200),
	jogo_encerrado(saiu), resultado(_, _, 0, sim, _, saiu),
	forall(dentro_mapa(X,Y), ( (X,Y) == (1,3) -> \+ pisou(X,Y) ; pisou(X,Y) )).

% pega o ouro, explora o resto, volta a (1,1) e sai
test(partida_itens_pega_ouro) :-
	carrega_mapa('testes/mapa_teste_itens.pl'), joga_politica(200),
	resultado(_, P, 1, sim, _, saiu), P > 450, \+ tile(3,1,'O'), once(tile(1,3,'U')).

% com os 3 ouros: planeja a volta; em (1,1) sai
test(tres_ouros_volta_e_sai) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), conhece_mapa, define_ouros(3),
	coloca(3,3,sul), uma_decisao(_), tem_plano,
	executa_plano, posicao(1,1,_), uma_decisao(sair).

% risco 50/50 de poço não compensa (arrisca/1 só é chamado quando não há fronteira)
test(nao_arrisca_poco_meio_a_meio) :-
	carrega_mapa('testes/mapa_teste_poco.pl'), executa(andar),
	once(entrada_risco((1,3), C1)), once(entrada_risco((2,2), C2)),
	C1 > 1000, C2 > 1000, \+ aceita_risco(C1).

% na casa do inimigo: anda em frente se a frente é segura; contra a parede, vira uma vez só
test(foge_do_inimigo) :-
	carrega_mapa('testes/mapa_teste_cadeia.pl'), conhece_mapa,
	pisa(2,3,leste), inimigo_aqui, uma_decisao(andar),
	coloca(2,3,sul), uma_decisao(andar),
	coloca(2,3,norte), uma_decisao(A), memberchk(A, [virar_direita, virar_esquerda]).

% chance de morrer na casa de um inimigo, pelo número de golpes
test(prob_morte_inimigo) :-
	prob_morte_inimigo(100, 1, P1), P1 =:= 0,
	prob_morte_inimigo(81, 1, P2), P2 =:= 0,
	prob_morte_inimigo(80, 1, P3), P3 > 0, P3 < 0.05,
	prob_morte_inimigo(100, 2, P4), P4 > 0.5,
	prob_morte_inimigo(25, 1, P5), P5 =:= 1.

% entrar no inimigo de frente para uma saída segura custa 1 golpe; sem saída, mais
test(entrada_alinhada_com_saida) :-
	carrega_mapa('testes/mapa_teste_cadeia.pl'), conhece_mapa,
	retract(user:perigo_confirmado(2,3,inimigo)), sincroniza_memoria,
	entrada_inimigo(2,3,leste,1), entrada_inimigo(2,3,norte,G), G > 1, !.

:- end_tests(fase4).
