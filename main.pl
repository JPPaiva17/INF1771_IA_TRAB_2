
:-dynamic posicao/3.
:-dynamic memory/3.
:-dynamic visitado/2.
:-dynamic certeza/2.
:-dynamic energia/1.
:-dynamic pontuacao/1.

%mapa real (carregado por carrega_mapa/1) e controle de partida
:-dynamic tile/3.
:-dynamic map_size/2.
:-dynamic mapa_atual/1.
:-dynamic diretorio_base/1.
:-dynamic ouros_coletados/1.
:-dynamic acoes_executadas/1.
:-dynamic fim_de_jogo/1.

%base de conhecimento do agente (ver seção "Base de conhecimento do agente")
:-dynamic percepcao/3.
:-dynamic pisou/2.
:-dynamic perigo_confirmado/3.
:-dynamic plano/2.
:-dynamic arriscou/3.

%arquivos de mapa sem caminho absoluto são procurados na pasta deste arquivo
:- prolog_load_context(directory, D), retractall(diretorio_base(_)), assert(diretorio_base(D)).

delete([], _, []).
delete([Elem|Tail], Del, Result) :-
    (   \+ Elem \= Del
    ->  delete(Tail, Del, Result)
    ;   Result = [Elem|Rest],
        delete(Tail, Del, Rest)
    ).
	


reset_game :- retractall(memory(_,_,_)), 
			retractall(visitado(_,_)), 
			retractall(certeza(_,_)),
			retractall(energia(_)),
			retractall(pontuacao(_)),
			retractall(posicao(_,_,_)),
			retractall(ouros_coletados(_)),
			retractall(acoes_executadas(_)),
			retractall(fim_de_jogo(_)),
			retractall(percepcao(_,_,_)),
			retractall(pisou(_,_)),
			retractall(perigo_confirmado(_,_,_)),
			retractall(plano(_,_)),
			retractall(arriscou(_,_,_)),
			assert(energia(100)),
			assert(pontuacao(0)),
			assert(ouros_coletados(0)),
			assert(acoes_executadas(0)),
			assert(posicao(1,1, norte)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Carregamento de mapas
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%carrega_mapa(+Arquivo): troca o mapa real e começa uma partida nova.
%Lê só os fatos tile/3 e map_size/2 do arquivo (não usa consult), para
%poder trocar de mapa várias vezes sem conflito entre arquivos.
carrega_mapa(Arquivo) :-
	diretorio_base(D),
	absolute_file_name(Arquivo, Caminho, [relative_to(D), extensions(['', pl]), access(read)]),
	retractall(tile(_,_,_)),
	retractall(map_size(_,_)),
	setup_call_cleanup(open(Caminho, read, S), le_termos_mapa(S), close(S)),
	map_size(_,_),
	retractall(mapa_atual(_)),
	assert(mapa_atual(Caminho)),
	novo_jogo, !.

le_termos_mapa(S) :- read_term(S, T, []),
	( T == end_of_file -> true ; guarda_termo_mapa(T), le_termos_mapa(S) ).

guarda_termo_mapa(tile(X,Y,Z)) :- !, assertz(tile(X,Y,Z)).
guarda_termo_mapa(map_size(X,Y)) :- !, assertz(map_size(X,Y)).
guarda_termo_mapa(_).

%reinicia a partida no mesmo mapa (recarrega o arquivo, pois pegar/0 remove ouro e itens do mapa)
reinicia_jogo :- mapa_atual(A), carrega_mapa(A).

%zera o agente e faz a primeira leitura dos sensores em [1,1]
novo_jogo :- reset_game, set_real(1,1), atualiza_obs.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Execução de ações e fim de partida
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%executa(+Acao): ponto único de entrada para qualquer ação (autoplay, teclado ou testes).
%Executa a ação, conta ações e ouros, e depois processa percepções e efeitos da nova posição.
%Falha se a partida já acabou ou se a ação não pôde ser feita (ex.: andar contra a parede).
executa(_) :- jogo_encerrado(_), !, fail.
executa(sair) :- !, sair.
executa(parar) :- !, parar.
executa(Acao) :- acao_basica(Acao), !,
	(brilho_aqui -> TinhaOuro = sim ; TinhaOuro = nao),
	call(Acao),
	incrementa_acoes,
	((Acao == pegar, TinhaOuro == sim, \+ brilho_aqui) -> incrementa_ouros ; true),
	atualiza_obs, verifica_player,
	avanca_plano(Acao).

acao_basica(andar).
acao_basica(virar_direita).
acao_basica(virar_esquerda).
acao_basica(pegar).

%o agente percebe brilho na posição atual (pela própria memória, não pelo mapa real)
brilho_aqui :- posicao(X,Y,_), memory(X,Y,L), memberchk(brilho, L), !.

incrementa_acoes :- retract(acoes_executadas(N)), N1 is N + 1, assert(acoes_executadas(N1)).
incrementa_ouros :- retract(ouros_coletados(N)), N1 is N + 1, assert(ouros_coletados(N1)).

%sair: encerra a partida com sucesso; só é possível na origem [1,1]
sair :- \+ jogo_encerrado(_), posicao(1,1,_), assert(fim_de_jogo(saiu)).

%parar: o agente desiste e encerra a partida onde estiver (sem ação segura ou útil)
parar :- \+ jogo_encerrado(_), assert(fim_de_jogo(parou)).

%jogo_encerrado(-Motivo): saiu | parou | morreu
jogo_encerrado(M) :- fim_de_jogo(M), !.
jogo_encerrado(morreu) :- posicao(_,_,morto).

%resumo da partida para registro de testes
resultado(Mapa, Pontuacao, Ouros, Sobreviveu, Acoes, Motivo) :-
	mapa_atual(Caminho), file_base_name(Caminho, Mapa),
	pontuacao(Pontuacao), ouros_coletados(Ouros), acoes_executadas(Acoes),
	(posicao(_,_,morto) -> Sobreviveu = nao ; Sobreviveu = sim),
	(jogo_encerrado(M) -> Motivo = M ; Motivo = em_andamento).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Controle de Status
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%atualiza pontuacao
atualiza_pontuacao(X):- pontuacao(P), retract(pontuacao(P)), NP is P + X, assert(pontuacao(NP)),!.

%atualiza energia
atualiza_energia(N):- energia(E), retract(energia(E)), NE is E + N, 
					(
					 (NE =<0, assert(energia(0)),posicao(X,Y,_),retract(posicao(_,_,_)), assert(posicao(X,Y,morto)),!);
					 (NE >100, assert(energia(100)),!);
					  (NE >0,assert(energia(NE)),!)
					 ).

%verifica situacao da nova posicao e atualiza energia e pontos
verifica_player :- posicao(X,Y,_), tile(X,Y,'P'), atualiza_energia(-100), atualiza_pontuacao(-1000),!.
verifica_player :- posicao(X,Y,_), tile(X,Y,'D'), random_between(-80,-50,D), atualiza_energia(D),!.
verifica_player :- posicao(X,Y,_), tile(X,Y,'d'), random_between(-50,-25,D), atualiza_energia(D),!.
verifica_player :- posicao(X,Y,Z), tile(X,Y,'T'), 
					map_size(SX,SY), random_between(1,SX,NX), random_between(1,SY,NY),
				retract(posicao(X,Y,Z)), assert(posicao(NX,NY,Z)), set_real(NX,NY), atualiza_obs, verifica_player,!.
verifica_player :- true.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Comandos
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%virar direita
virar_direita :- posicao(X,Y, norte), retract(posicao(_,_,_)), assert(posicao(X, Y, leste)),atualiza_pontuacao(-1),!.
virar_direita :- posicao(X,Y, oeste), retract(posicao(_,_,_)), assert(posicao(X, Y, norte)),atualiza_pontuacao(-1),!.
virar_direita :- posicao(X,Y, sul), retract(posicao(_,_,_)), assert(posicao(X, Y, oeste)),atualiza_pontuacao(-1),!.
virar_direita :- posicao(X,Y, leste), retract(posicao(_,_,_)), assert(posicao(X, Y, sul)),atualiza_pontuacao(-1),!.

%virar esquerda
virar_esquerda :- posicao(X,Y, norte), retract(posicao(_,_,_)), assert(posicao(X, Y, oeste)),atualiza_pontuacao(-1),!.
virar_esquerda :- posicao(X,Y, oeste), retract(posicao(_,_,_)), assert(posicao(X, Y, sul)),atualiza_pontuacao(-1),!.
virar_esquerda :- posicao(X,Y, sul), retract(posicao(_,_,_)), assert(posicao(X, Y, leste)),atualiza_pontuacao(-1),!.
virar_esquerda :- posicao(X,Y, leste), retract(posicao(_,_,_)), assert(posicao(X, Y, norte)),atualiza_pontuacao(-1),!.

%andar
andar :- posicao(X,Y,P), P = norte, map_size(_,MAX_Y), Y < MAX_Y, YY is Y + 1, 
         retract(posicao(X,Y,_)), assert(posicao(X, YY, P)), 
		 %((retract(certeza(X,YY)), assert(certeza(X,YY))); assert(certeza(X,YY))),
		 set_real(X,YY),
		 ((retract(visitado(X,Y)), assert(visitado(X,Y))); assert(visitado(X,Y))),atualiza_pontuacao(-1),!.
		 
andar :- posicao(X,Y,P), P = sul,  Y > 1, YY is Y - 1, 
         retract(posicao(X,Y,_)), assert(posicao(X, YY, P)), 
		 %((retract(certeza(X,YY)), assert(certeza(X,YY))); assert(certeza(X,YY))),
		 set_real(X,YY),
		 ((retract(visitado(X,Y)), assert(visitado(X,Y))); assert(visitado(X,Y))),atualiza_pontuacao(-1),!.

andar :- posicao(X,Y,P), P = leste, map_size(MAX_X,_), X < MAX_X, XX is X + 1, 
         retract(posicao(X,Y,_)), assert(posicao(XX, Y, P)), 
		 %((retract(certeza(XX,Y)), assert(certeza(XX,Y))); assert(certeza(XX,Y))),
		 set_real(XX,Y),
		 ((retract(visitado(X,Y)), assert(visitado(X,Y))); assert(visitado(X,Y))),atualiza_pontuacao(-1),!.

andar :- posicao(X,Y,P), P = oeste,  X > 1, XX is X - 1, 
         retract(posicao(X,Y,_)), assert(posicao(XX, Y, P)), 
		 %((retract(certeza(XX,Y)), assert(certeza(XX,Y))); assert(certeza(XX,Y))),
		 set_real(XX,Y),
		 ((retract(visitado(X,Y)), assert(visitado(X,Y))); assert(visitado(X,Y))),atualiza_pontuacao(-1),!.
		 
%pegar	
pegar :- posicao(X,Y,_), tile(X,Y,'O'), retract(tile(X,Y,'O')), assert(tile(X,Y,'')), atualiza_pontuacao(-5), atualiza_pontuacao(500),set_real(X,Y),!. 
pegar :- posicao(X,Y,_), tile(X,Y,'U'), retract(tile(X,Y,'U')), assert(tile(X,Y,'')), atualiza_pontuacao(-5), atualiza_energia(50),set_real(X,Y),!. 
pegar :- atualiza_pontuacao(-5),!.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Funcoes Auxiliares de navegação e observação
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		 
%Define as 4 adjacencias		 
adjacente(X, Y) :- posicao(PX, Y, _), map_size(MAX_X,_),PX < MAX_X, X is PX + 1.  
adjacente(X, Y) :- posicao(PX, Y, _), PX > 1, X is PX - 1.  
adjacente(X, Y) :- posicao(X, PY, _), map_size(_,MAX_Y),PY < MAX_Y, Y is PY + 1.  
adjacente(X, Y) :- posicao(X, PY, _), PY > 1, Y is PY - 1.  

%cria lista com a adjacencias
adjacentes(L) :- findall(Z,(adjacente(X,Y),tile(X,Y,Z)),L).

%define observacoes locais
observacao_loc(brilho,L) :- member('O',L).
observacao_loc(reflexo,L) :- member('U',L).

%define observacoes adjacentes
observacao_adj(brisa,L) :- member('P',L).
observacao_adj(palmas,L) :- member('T',L).
observacao_adj(passos,L) :- member('D',L).
observacao_adj(passos,L) :- member('d',L).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tratamento de KB e observações
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%cria lista de observacoes (sensores: leem o mapa real ao redor da posição atual)
observacoes(X) :- adjacentes(L), findall(Y, observacao_adj(Y,L), X).

%consulta e processa observações: guarda o que foi percebido aqui e refaz as inferências
%(substitui a versão original, cuja dedução de "única casa candidata" podia marcar
% um perigo como certo sem que ele fosse o único possível)
atualiza_obs :- registra_percepcao, infere.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Base de conhecimento do agente
%%
%% Fatos que o agente acumula (nenhum deles é o mapa real):
%%   percepcao(X,Y,L)          sinais sentidos em (X,Y): lista de brisa/palmas/passos
%%   pisou(X,Y)                o agente esteve fisicamente em (X,Y) e sabe o que há ali
%%   visitado(X,Y)             casa de onde o agente saiu andando
%%   perigo_confirmado(X,Y,P)  perigo P (poco/teleporte/inimigo) provado em (X,Y)
%% Derivados para a interface: memory/3 e certeza/2.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%perigo e o sinal que ele provoca nas casas vizinhas
sinal(poco, brisa).
sinal(teleporte, palmas).
sinal(inimigo, passos).

perigo(P) :- sinal(P, _).

dentro_mapa(X,Y) :- map_size(MX,MY), between(1,MX,X), between(1,MY,Y).

%vizinha(+X,+Y,-VX,-VY): as 4 casas vizinhas dentro do mapa
vizinha(X,Y,VX,Y) :- VX is X + 1, map_size(MX,_), VX =< MX.
vizinha(X,Y,VX,Y) :- VX is X - 1, VX >= 1.
vizinha(X,Y,X,VY) :- VY is Y + 1, map_size(_,MY), VY =< MY.
vizinha(X,Y,X,VY) :- VY is Y - 1, VY >= 1.

%guarda a percepção da posição atual
registra_percepcao :- posicao(X,Y,_), observacoes(L0), sort(L0, L),
	retractall(percepcao(X,Y,_)), assert(percepcao(X,Y,L)).

%casa já percorrida pelo agente (a posição atual também conta)
visitada(X,Y) :- visitado(X,Y).
visitada(X,Y) :- posicao(X,Y,D), D \= morto, \+ visitado(X,Y).

%sem_perigo(X,Y,P): o agente sabe que (X,Y) não contém o perigo P
% 1) esteve lá e não encontrou P
sem_perigo(X,Y,P) :- pisou(X,Y), !, sinal(P,S), \+ (memory(X,Y,L), member(S,L)).
% 2) alguma vizinha foi percebida sem o sinal de P
sem_perigo(X,Y,P) :- sinal(P,S), vizinha(X,Y,VX,VY), percepcao(VX,VY,L), \+ member(S,L), !.
% 3) já foi provado outro perigo ali (cada casa tem um único elemento)
sem_perigo(X,Y,P) :- perigo_confirmado(X,Y,P2), P2 \= P, !.

%pode_ter(X,Y,P): nada do que o agente sabe exclui o perigo P em (X,Y)
pode_ter(X,Y,P) :- perigo(P), \+ sem_perigo(X,Y,P).

%a casa tem ao menos uma vizinha já percebida (há alguma informação sobre ela)
informada(X,Y) :- pisou(X,Y), !.
informada(X,Y) :- vizinha(X,Y,VX,VY), percepcao(VX,VY,_), !.

%%% Consultas usadas pela decisão (fase 3/4) %%%

%segura: nenhum perigo é possível em (X,Y)
segura(X,Y) :- dentro_mapa(X,Y), informada(X,Y), \+ pode_ter(X,Y,_).

%perigo_possivel: P não está excluído nem provado em (X,Y)
perigo_possivel(X,Y,P) :- dentro_mapa(X,Y), \+ perigo_confirmado(X,Y,_), pode_ter(X,Y,P).

%desconhecida: o agente não tem nenhuma informação sobre (X,Y)
desconhecida(X,Y) :- dentro_mapa(X,Y), \+ informada(X,Y).

%fronteira: casa segura onde o agente ainda não esteve
fronteira(X,Y) :- segura(X,Y), \+ visitada(X,Y), \+ pisou(X,Y).

%%% Inferência %%%

%novo_perigo(X,Y,P): perigo P provado em (X,Y) e ainda não registrado
% 1) o agente esteve lá e encontrou P (teleporte que o levou, inimigo que o atacou, poço)
novo_perigo(X,Y,P) :- pisou(X,Y), memory(X,Y,L), sinal(P,S), member(S,L),
	\+ perigo_confirmado(X,Y,P).
% 2) uma casa percebeu o sinal de P e só uma vizinha dela ainda pode ter P
novo_perigo(X,Y,P) :- percepcao(VX,VY,L), sinal(P,S), member(S,L),
	findall((NX,NY), (vizinha(VX,VY,NX,NY), pode_ter(NX,NY,P)), [(X,Y)]),
	\+ perigo_confirmado(X,Y,P).

%aplica as regras até não haver nada novo (cada prova pode excluir outros perigos e gerar novas provas)
infere :- novo_perigo(X,Y,P), !, assert(perigo_confirmado(X,Y,P)), infere.
infere :- sincroniza_memoria.

%reescreve memory/3 e certeza/2 das casas onde o agente não esteve, para a interface e o show_mem:
%memory = sinais dos perigos ainda possíveis; certeza = casa segura ou perigo provado
sincroniza_memoria :-
	forall(( dentro_mapa(X,Y), \+ pisou(X,Y) ), sincroniza_casa(X,Y)).

sincroniza_casa(X,Y) :-
	retractall(memory(X,Y,_)), retractall(certeza(X,Y)),
	( informada(X,Y) ->
		findall(S, (pode_ter(X,Y,P), sinal(P,S)), L),
		assert(memory(X,Y,L)),
		( (L == [] ; perigo_confirmado(X,Y,_)) -> assert(certeza(X,Y)) ; true )
	; true ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Planejamento de rotas
%%
%% Busca em largura sobre estados (X, Y, Direção) usando só o que o agente sabe:
%% passa apenas por casas seguras (segura/2). Virar e andar custam 1 ponto cada,
%% então a rota com menos ações é também a de menor custo (conta as viradas).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%direção à direita / à esquerda
direita(norte, leste).
direita(leste, sul).
direita(sul, oeste).
direita(oeste, norte).
esquerda(D, E) :- direita(E, D).

%casa à frente de (X,Y) olhando para D
a_frente(X, Y, norte, X, Y1) :- Y1 is Y + 1, map_size(_, MY), Y1 =< MY.
a_frente(X, Y, sul,   X, Y1) :- Y1 is Y - 1, Y1 >= 1.
a_frente(X, Y, leste, X1, Y) :- X1 is X + 1, map_size(MX, _), X1 =< MX.
a_frente(X, Y, oeste, X1, Y) :- X1 is X - 1, X1 >= 1.

%efeito(+Estado, +Acao, -NovoEstado): resultado esperado de uma ação (sem surpresas)
efeito(e(X,Y,D), virar_direita,  e(X,Y,D2)) :- direita(D, D2).
efeito(e(X,Y,D), virar_esquerda, e(X,Y,D2)) :- esquerda(D, D2).
efeito(e(X,Y,D), andar,          e(X2,Y2,D)) :- a_frente(X, Y, D, X2, Y2).
efeito(e(X,Y,D), pegar,          e(X,Y,D)).

estado_atual(e(X,Y,D)) :- posicao(X,Y,D), D \= morto.

%rota_ate(+Alvos, -Acoes): menor sequência de ações da posição atual até qualquer casa de Alvos
%(lista de (X,Y)). Só atravessa casas seguras; a casa-alvo em si pode não ser segura
%(útil para arriscar uma casa de propósito). Falha se não houver caminho conhecido.
rota_ate(Alvos, Acoes) :- estado_atual(E), rota_de(E, Alvos, Acoes).

rota_de(E, Alvos, []) :- atinge(E, Alvos), !.
rota_de(E, Alvos, Acoes) :-
	E = e(X0,Y0,_),
	empty_assoc(V0), put_assoc(E, V0, t, V),
	bfs([E-[]], V, Alvos, (X0,Y0), Rev), !,
	reverse(Rev, Acoes).

%bfs(+Camada, +Vistos, +Alvos, +Origem, -AcoesInvertidas): expande uma camada (mesmo custo) por vez
bfs(Camada, Vistos, Alvos, Origem, Rev) :-
	Camada \== [],
	findall(E2-[A|R],
	        ( member(E-R, Camada), efeito(E, A, E2), A \== pegar, transitavel(E2, Alvos, Origem) ),
	        Candidatos),
	( member(E2-Rev, Candidatos), atinge(E2, Alvos) -> true
	; novos(Candidatos, Vistos, Proxima, Vistos2),
	  bfs(Proxima, Vistos2, Alvos, Origem, Rev) ).

%um alvo é uma casa (X,Y) ou um estado e(X,Y,D) (entrar na casa olhando para D)
atinge(e(X,Y,D), Alvos) :- ( memberchk((X,Y), Alvos) -> true ; memberchk(e(X,Y,D), Alvos) ).

%só pode entrar em casa segura ou no alvo; na casa de origem pode girar mesmo que
%ela não seja segura (ex.: o agente está na casa de um inimigo)
transitavel(E, Alvos, Origem) :- E = e(X,Y,_),
	( atinge(E, Alvos) -> true
	; memberchk(e(X,Y,_), Alvos) -> fail          % casa-alvo, mas na direção errada
	; (X,Y) == Origem -> true
	; segura(X,Y) ).

%descarta estados já vistos (mantém o primeiro caminho encontrado para cada estado)
novos([], V, [], V).
novos([E-R|T], V0, Prox, V) :-
	( get_assoc(E, V0, _) -> Prox = Prox1, V1 = V0
	; put_assoc(E, V0, t, V1), Prox = [E-R|Prox1] ),
	novos(T, V1, Prox1, V).

%custo_rota(+Alvos, -Custo): número de ações (= pontos gastos) até o alvo mais próximo
custo_rota(Alvos, Custo) :- rota_ate(Alvos, Acoes), length(Acoes, Custo).

%%% Plano em andamento %%%
%plano(Acoes, EstadoEsperado): ações que faltam e o estado em que o agente deve
%estar antes da próxima. Se algo inesperado acontecer (teleporte, ação diferente da
%planejada), o plano é descartado e a decisão planeja de novo.

%planeja(+Alvos): calcula e guarda a rota até o alvo mais próximo
planeja(Alvos) :- rota_ate(Alvos, Acoes), Acoes \== [], estado_atual(E),
	retractall(plano(_,_)), assert(plano(Acoes, E)).

%proxima_acao_plano(-A): próxima ação do plano, se o agente está onde o plano espera
proxima_acao_plano(A) :- plano([A|_], E), estado_atual(E), !.
proxima_acao_plano(_) :- retractall(plano(_,_)), fail.

tem_plano :- plano(_,_).
cancela_plano :- retractall(plano(_,_)).

%avanca_plano(+Acao): chamado por executa/1 depois de cada ação
avanca_plano(Acao) :-
	( plano([Acao|Resto], E), efeito(E, Acao, Esperado) ->
		retractall(plano(_,_)),
		( Resto \== [], estado_atual(Esperado) -> assert(plano(Resto, Esperado)) ; true )
	; retractall(plano(_,_)) ).

%vai_para(+X,+Y): depuração no swipl — planeja e executa a rota inteira até (X,Y)
vai_para(X, Y) :- planeja([(X,Y)]), executa_plano.
executa_plano :- proxima_acao_plano(A), !, executa(A), executa_plano.
executa_plano.

%Quando posicao é visitada, atualiza memoria de posicao com a informação real do mapa 
set_real(X,Y):- ((retract(certeza(X,Y)), assert(certeza(X,Y)),!); assert(certeza(X,Y))), set_real2(X,Y),
				((pisou(X,Y),!); assert(pisou(X,Y))),!.
set_real2(X,Y):- tile(X,Y,'P'), ((retract(memory(X,Y,_)),assert(memory(X,Y,[brisa])),!);assert(memory(X,Y,[brisa]))),!.
set_real2(X,Y):- tile(X,Y,'O'), ((retract(memory(X,Y,_)),assert(memory(X,Y,[brilho])),!);assert(memory(X,Y,[brilho]))),!.
set_real2(X,Y):- tile(X,Y,'T'), ((retract(memory(X,Y,_)),assert(memory(X,Y,[palmas])),!);assert(memory(X,Y,[palmas]))),!.
set_real2(X,Y):- ((tile(X,Y,'D'),!); tile(X,Y,'d')), ((retract(memory(X,Y,_)),assert(memory(X,Y,[passos])),!);assert(memory(X,Y,[passos]))),!.
set_real2(X,Y):- tile(X,Y,'U'), ((retract(memory(X,Y,_)),assert(memory(X,Y,[reflexo])),!);assert(memory(X,Y,[reflexo]))),!.
set_real2(X,Y):- tile(X,Y,''), ((retract(memory(X,Y,_)),assert(memory(X,Y,[])),!);assert(memory(X,Y,[]))),!.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Mostra mapa real
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
show_player(X,Y) :- posicao(X,Y, norte), write('^'),!.
show_player(X,Y) :- posicao(X,Y, oeste), write('<'),!.
show_player(X,Y) :- posicao(X,Y, leste), write('>'),!.
show_player(X,Y) :- posicao(X,Y, sul), write('v'),!.
show_player(X,Y) :- posicao(X,Y, morto), write('+'),!.

%show_position(X,Y) :- show_player(X,Y),!.
show_position(X,Y) :- (show_player(X,Y); write(' ')), tile(X,Y,Z), ((Z='', write(' '));write(Z)),!.

show_map :- map_size(_,MAX_Y), show_map(1,MAX_Y),!.
show_map(X,Y) :- Y >= 1, map_size(MAX_X,_), X =< MAX_X, show_position(X,Y), write(' | '), XX is X + 1, show_map(XX, Y),!.
show_map(X,Y) :- Y >= 1, map_size(X,_),YY is Y - 1, write(Y), nl, show_map(1, YY),!.
show_map(_,0) :- energia(E), pontuacao(P), write('E: '), write(E), write('   P: '), write(P),!.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Mostra mapa conhecido
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

show_mem_info(X,Y) :- memory(X,Y,Z), 
		((visitado(X,Y), write('.'),!); (\+certeza(X,Y), write('?'),!); (certeza(X,Y), write('!'))),
		((member(brisa, Z), write('P'));write(' ')),
		((member(palmas, Z), write('T'));write(' ')),
		((member(brilho, Z), write('O'));write(' ')),
		((member(passos, Z), write('D'));write(' ')),
		((member(reflexo, Z), write('U'));write(' ')),!.

show_mem_info(X,Y) :- \+memory(X,Y,[]), 
			((visitado(X,Y), write('.'),!); (\+certeza(X,Y), write('?'),!); (certeza(X,Y), write('!'))),
			write('     '),!.		
		
		

show_mem_position(X,Y) :- posicao(X,Y,_), 
		((visitado(X,Y), write('.'),!); (certeza(X,Y), write('!'),!); write(' ')),
		write(' '), show_player(X,Y),
		((memory(X,Y,Z),
		((member(brilho, Z), write('O'));write(' ')),
		((member(passos, Z), write('D'));write(' ')),
		((member(reflexo, Z), write('U'));write(' ')),!);
		(write('   '),!)).

		
show_mem_position(X,Y) :- show_mem_info(X,Y),!.


show_mem :- map_size(_,MAX_Y), show_mem(1,MAX_Y),!.
show_mem(X,Y) :- Y >= 1, map_size(MAX_X,_), X =< MAX_X, show_mem_position(X,Y), write('|'), XX is X + 1, show_mem(XX, Y),!.
show_mem(X,Y) :- Y >= 1, map_size(X,_),YY is Y - 1, write(Y), nl, show_mem(1, YY),!.
show_mem(_,0) :- energia(E), pontuacao(P), write('E: '), write(E), write('   P: '), write(P),!.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Decisão: executa_acao(-Acao)
%%
%% Regras em ordem de prioridade: a primeira que se aplica decide, e todas
%% terminam com corte (o Python pede todas as soluções e usa a primeira).
%% Usa só a base de conhecimento do agente (nunca tile/3, adjacentes/1 ou
%% observacoes/1). Só devolve a ação; quem executa é executa/1.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% Parâmetros da estratégia %%%
:- dynamic total_ouros/1, valor_ouro/1, voltar_ao_inicio/1, fator_ganho/1, limite_acoes/1, peso_teleporte/1.
total_ouros(3).          % regra do jogo: 3 ouros por mapa
valor_ouro(495).         % +500 do ouro − 5 do pegar
voltar_ao_inicio(sim).   % sim: volta a (1,1) e sai; nao: para onde estiver
fator_ganho(0.5).        % arrisca se o custo esperado ≤ fator × valor dos ouros que faltam
limite_acoes(1500).      % trava de segurança contra laços
peso_teleporte(16).      % multiplica o custo estimado do teletransportador: nos testes, o sorteio
                         % de posição foi bem pior que a estimativa, então ele fica como último recurso

ouros_faltando(F) :- total_ouros(T), ouros_coletados(N), F is max(0, T - N).

executa_acao(_) :- jogo_encerrado(_), !, fail.                           % 1. morto ou encerrado
executa_acao(A) :- inimigo_aqui, foge(A), !.                            % 1b. sai da casa do inimigo
executa_acao(pegar) :- brilho_aqui, !.                                   % 2. ouro aqui
executa_acao(pegar) :- reflexo_aqui, vale_pegar_item, !.                 % 3. item de energia aqui
executa_acao(A) :- tem_plano, proxima_acao_plano(A), !.                  % 4. plano em andamento
executa_acao(A) :- ouros_faltando(0), !, encerra(A).                     % 5. tem os 3 ouros
executa_acao(A) :- acoes_executadas(N), limite_acoes(L), N >= L, !, encerra(A).
executa_acao(A) :- explora(A), !.                                        % 6. fronteira segura
executa_acao(A) :- busca_item(A), !.                                     % 7a. recarrega antes de arriscar
executa_acao(A) :- arrisca(A), !.                                        % 7b. casa de menor risco
executa_acao(A) :- encerra(A), !.                                        % 7c. não compensa arriscar
executa_acao(A) :- acao_aleatoria(A).                                    % 8. último recurso

%%% 1b. Casa de inimigo: cada ação feita ali leva outro golpe, então sai com o mínimo de ações %%%
inimigo_aqui :- posicao(X,Y,_), pisou(X,Y), memory(X,Y,L), memberchk(passos, L), !.
foge(andar) :- posicao(X,Y,D), a_frente(X,Y,D,X2,Y2), segura(X2,Y2), !.
foge(A) :- posicao(X,Y,_), findall((VX,VY), (vizinha(X,Y,VX,VY), segura(VX,VY)), L), L \== [],
	rota_ate(L, [A|_]), !.

%%% 3. Item de energia %%%
%o agente esteve na casa e viu reflexo (o item continua lá até ser pego)
item_conhecido(X,Y) :- pisou(X,Y), memory(X,Y,L), memberchk(reflexo, L).
reflexo_aqui :- posicao(X,Y,_), item_conhecido(X,Y), !.

%com energia ≤ 50 o item rende os +50 inteiros; com ≤ 80 vale se o agente vai precisar arriscar
vale_pegar_item :- energia(E), E =< 50, !.
vale_pegar_item :- energia(E), E =< 80, \+ fronteira(_,_), !.

%%% 6. Exploração segura %%%
explora(A) :- findall((X,Y), fronteira(X,Y), F), F \== [], planeja(F), proxima_acao_plano(A).

%%% 7a. Buscar um item conhecido antes de arriscar (inimigo tira até 80 de energia) %%%
busca_item(A) :- energia(E), E =< 80,
	findall((X,Y), item_conhecido(X,Y), Itens), Itens \== [],
	planeja(Itens), proxima_acao_plano(A).

%%% 7b. Arriscar %%%
%candidatas: casas não pisadas, ainda não seguras, sem poço provado e vizinhas de uma casa
%segura (ou da posição atual); e teletransportadores já conhecidos, como forma de sair
%de uma região sem saída. Só valem se houver rota segura até a vizinha (rota_ate decide).
candidata_risco(X,Y) :- dentro_mapa(X,Y), \+ pisou(X,Y), \+ segura(X,Y),
	\+ perigo_confirmado(X,Y,poco),
	once(( vizinha(X,Y,VX,VY), ( segura(VX,VY) ; posicao(VX,VY,_) ) )).
candidata_risco(X,Y) :- pisou(X,Y), perigo_confirmado(X,Y,teleporte).

%prob_perigo(+X,+Y,+P,-Prob): estimativa da chance de o perigo P estar em (X,Y)
prob_perigo(X,Y,P,1) :- perigo_confirmado(X,Y,P), !.
prob_perigo(X,Y,P,0) :- \+ pode_ter(X,Y,P), !.
prob_perigo(X,Y,P,Prob) :- sinal(P,S),
	findall(Pv, ( vizinha(X,Y,VX,VY), percepcao(VX,VY,L), memberchk(S,L),
	              prob_pela_vizinha(VX,VY,X,Y,P,Pv) ), Ps),
	( Ps == [] -> prob_a_priori(P, Prob) ; max_list(Ps, Prob) ).

%uma casa que sentiu o sinal "divide" a culpa entre as vizinhas que ainda podem ter o perigo;
%se o sinal já está explicado por um perigo provado em outra vizinha, a chance é pequena
prob_pela_vizinha(VX,VY,X,Y,P,Pv) :-
	( vizinha(VX,VY,NX,NY), (NX,NY) \== (X,Y), perigo_confirmado(NX,NY,P) -> Pv = 0.15
	; aggregate_all(count, (vizinha(VX,VY,NX,NY), pode_ter(NX,NY,P)), K), Pv is 1 / K ).

%casa sem nenhuma informação: proporção do elemento no mapa (8 P, 4 T, 4 inimigos em 144)
prob_a_priori(poco, P) :- P is 8 / 144.
prob_a_priori(teleporte, P) :- P is 4 / 144.
prob_a_priori(inimigo, P) :- P is 4 / 144.

%entrada_risco(-Alvo, -Custo): uma forma de entrar numa candidata e a perda esperada.
%Se pode haver inimigo, o alvo inclui a direção de entrada: o inimigo golpeia a cada ação
%feita na casa dele, então o melhor é entrar já de frente para uma saída segura.
entrada_risco(Alvo, Custo) :- candidata_risco(X,Y),
	( pode_ter(X,Y,inimigo) -> entrada_inimigo(X,Y,D,Golpes), Alvo = e(X,Y,D)
	; Alvo = (X,Y), Golpes = 1 ),
	custo_risco(X,Y,Golpes,Custo).

%entrando em (X,Y) olhando para D (vindo da casa de trás, que é segura ou é a atual),
%Golpes = ações feitas lá dentro: 1 se a casa à frente é segura, 2 se uma lateral é,
%senão 3 (meia-volta para a casa de onde veio)
entrada_inimigo(X,Y,D,Golpes) :- direita(D,_), oposta(D,DT),
	a_frente(X,Y,DT,BX,BY), ( segura(BX,BY) ; posicao(BX,BY,_) ),
	( a_frente(X,Y,D,FX,FY), segura(FX,FY) -> Golpes = 1
	; ( direita(D,L) ; esquerda(D,L) ), a_frente(X,Y,L,LX,LY), segura(LX,LY) -> Golpes = 2
	; Golpes = 3 ).

oposta(D, O) :- direita(D, R), direita(R, O).

%custo_risco(+X,+Y,+Golpes,-Custo): perda esperada de pontos ao entrar em (X,Y)
%V = valor dos ouros que faltam (perdidos se o agente morrer)
custo_risco(X,Y,Golpes,Custo) :-
	ouros_faltando(F), valor_ouro(VO), V is F * VO, energia(E),
	findall(C, ( perigo(P), prob_perigo(X,Y,P,Pr), Pr > 0,
	             custo_perigo(P,X,Y,V,E,Golpes,CP), C is Pr * CP ), Cs),
	sum_list(Cs, Custo).

custo_perigo(poco, _, _, V, _, _, C) :- C is 1000 + V.
%teletransporte: chance de cair num poço (8 em 144) + desvio; fica mais caro a cada uso
custo_perigo(teleporte, _, _, V, _, _, C) :- usos_teleporte(N), peso_teleporte(W),
	C is W * (8/144 * (1000 + V) + 20) * (1 + N).
%inimigo: chance de morrer com aqueles golpes + energia perdida
custo_perigo(inimigo, _, _, V, E, G, C) :- prob_morte_inimigo(E, G, PM), C is PM * V + 10 * G.

%quantas vezes o agente já entrou de propósito num teletransportador conhecido (todos somados)
usos_teleporte(N) :- aggregate_all(sum(K), arriscou(_,_,K), N).

%prob_morte_inimigo(+E,+Golpes,-P): chance de morrer levando Golpes golpes com energia E
%(d e D são indistinguíveis: metade de chance cada; D tira 50..80, d tira 25..50)
prob_morte_inimigo(E, G, P) :-
	prob_soma_atinge(G, 50, 80, E, PD), prob_soma_atinge(G, 25, 50, E, Pd),
	P is (PD + Pd) / 2.

%chance de a soma de K danos sorteados em Min..Max chegar a E
:- table prob_soma_atinge/5.
prob_soma_atinge(_, _, _, E, 1) :- E =< 0, !.
prob_soma_atinge(0, _, _, _, 0) :- !.
prob_soma_atinge(K, Min, Max, E, P) :- K1 is K - 1,
	aggregate_all(sum(P1), ( between(Min, Max, Dano), E1 is E - Dano,
	                         prob_soma_atinge(K1, Min, Max, E1, P1) ), S),
	P is S / (Max - Min + 1).

%só arrisca se a perda esperada for menor que uma fração do que ainda dá para ganhar
aceita_risco(Custo) :- ouros_faltando(F), F > 0, valor_ouro(VO), fator_ganho(G), Custo =< G * F * VO.

%ordena as candidatas pelo risco; entre as de risco parecido (±5) vai à mais próxima
arrisca(A) :-
	findall(C-Alvo, entrada_risco(Alvo, C), L0),
	keysort(L0, L),
	escolhe_risco(L, A).

escolhe_risco([C|_], _) :- C = Custo-_, \+ aceita_risco(Custo), !, fail.
escolhe_risco(L, A) :-
	L = [C0-_|_], Lim is C0 + 5,
	partition([C-_]>>(C =< Lim), L, Grupo0, Resto),
	pairs_values(Grupo0, Grupo),
	( planeja(Grupo) -> registra_risco, proxima_acao_plano(A)
	; escolhe_risco(Resto, A) ).

%anota o uso de um teletransportador conhecido (para não usá-lo em laço)
registra_risco :- plano(Acoes, E), destino(E, Acoes, e(X,Y,_)),
	( pisou(X,Y), perigo_confirmado(X,Y,teleporte) ->
		( arriscou(X,Y,N) -> true ; N = 0 ), N1 is N + 1,
		retractall(arriscou(X,Y,_)), assert(arriscou(X,Y,N1))
	; true ), !.

destino(E, [], E).
destino(E, [A|R], F) :- once(efeito(E, A, E1)), destino(E1, R, F).

%%% 5 e 7c. Encerrar: volta a (1,1) por casas seguras e sai; sem rota, para onde está %%%
encerra(sair) :- voltar_ao_inicio(sim), posicao(1,1,_), !.
encerra(A) :- voltar_ao_inicio(sim), planeja([(1,1)]), proxima_acao_plano(A), !.
encerra(parar).

%%% 8. Último recurso (sugestão do professor); na prática encerra/1 sempre decide antes
acao_aleatoria(X) :- L = [virar_esquerda, virar_direita, andar, pegar], random_member(X, L).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%mapa padrão; carrega_mapa/1 troca por outro (ex.: carrega_mapa('mapa-dificil.pl'))
:- initialization(carrega_mapa('mapa.pl')).




