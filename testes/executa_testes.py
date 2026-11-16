"""Executor de testes sem interface (Fase 5).

Joga partidas completas com o agente Prolog, do mesmo jeito que o gmap.py no
autoplay: pergunta executa_acao(X) e executa a ação com executa(X), que já
processa percepções e efeitos (atualiza_obs, verifica_player). Repete até a
partida acabar (morreu, saiu ou parou).

Grava em testes/resultados/:
  resultados.csv  uma linha por partida (pontuação, ouros, sobrevivência, ações...)
  resumo.md       tabela com médias por mapa e a verificação de que a decisão
                  não consulta o mapa real

Uso (na pasta do projeto, com o venv ativo):
  python testes/executa_testes.py                  # 30 partidas por mapa
  python testes/executa_testes.py -n 100           # 100 partidas por mapa
  python testes/executa_testes.py --mapas mapa-dificil.pl
"""

import argparse
import csv
import datetime
import os
import pathlib
import statistics
import sys
import time

from pyswip import Prolog

PROJETO = pathlib.Path(__file__).resolve().parent.parent
MAPAS_PADRAO = ['mapa-facil.pl', 'mapa-medio.pl', 'mapa-dificil.pl']
LIMITE_PASSOS = 3000  # trava de segurança; a política encerra bem antes
CAMPOS = ['mapa', 'execucao', 'semente', 'pontuacao', 'ouros', 'sobreviveu',
          'acoes', 'motivo', 'decisao_media_ms', 'decisao_max_ms']


def atomo(texto):
    """Escreve um texto como átomo Prolog entre aspas simples."""
    return "'" + str(texto).replace('\\', '\\\\').replace("'", "\\'") + "'"


def consulta(prolog, objetivo):
    return list(prolog.query(objetivo))


def joga_partida(prolog, mapa, semente):
    """Joga uma partida inteira e devolve o registro dela."""
    consulta(prolog, 'set_random(seed(%d))' % semente)  # dano e teletransporte reproduzíveis
    if not consulta(prolog, 'carrega_mapa(%s)' % atomo(mapa)):
        raise RuntimeError('não foi possível carregar o mapa ' + mapa)

    tempos = []
    for _ in range(LIMITE_PASSOS):
        if consulta(prolog, 'jogo_encerrado(_)'):
            break
        inicio = time.perf_counter()
        decisao = consulta(prolog, 'executa_acao(X)')
        tempos.append(time.perf_counter() - inicio)
        if not decisao:
            break
        consulta(prolog, 'executa(%s)' % decisao[0]['X'])

    r = consulta(prolog, 'resultado(M, P, O, S, A, Motivo)')[0]
    return {
        'mapa': str(r['M']),
        'semente': semente,
        'pontuacao': int(r['P']),
        'ouros': int(r['O']),
        'sobreviveu': str(r['S']),
        'acoes': int(r['A']),
        'motivo': str(r['Motivo']),
        'decisao_media_ms': round(1000 * statistics.mean(tempos), 2) if tempos else 0,
        'decisao_max_ms': round(1000 * max(tempos), 2) if tempos else 0,
    }


def resume(registros):
    """Estatísticas de um mapa."""
    pts = [r['pontuacao'] for r in registros]
    ouros = [r['ouros'] for r in registros]
    acoes = [r['acoes'] for r in registros]
    vivos = sum(1 for r in registros if r['sobreviveu'] == 'sim')
    motivos = {}
    for r in registros:
        motivos[r['motivo']] = motivos.get(r['motivo'], 0) + 1
    return {
        'n': len(registros),
        'pts_media': statistics.mean(pts),
        'pts_desvio': statistics.stdev(pts) if len(pts) > 1 else 0.0,
        'pts_min': min(pts),
        'pts_max': max(pts),
        'ouros_media': statistics.mean(ouros),
        'tres_ouros': sum(1 for o in ouros if o == 3),
        'vivos': vivos,
        'acoes_media': statistics.mean(acoes),
        'decisao_max_ms': max(r['decisao_max_ms'] for r in registros),
        'motivos': ', '.join('%s %d' % (m, c) for m, c in sorted(motivos.items())),
    }


def parametros(prolog):
    nomes = ['fator_ganho', 'peso_teleporte', 'voltar_ao_inicio', 'limite_acoes']
    valores = {}
    for nome in nomes:
        r = consulta(prolog, '%s(V)' % nome)
        valores[nome] = str(r[0]['V']) if r else '?'
    return valores


def escreve_resumo(caminho, por_mapa, proibidos, params, n, semente_base):
    agora = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
    linhas = [
        '# Registro de testes do agente',
        '',
        'Gerado por `python testes/executa_testes.py` em %s.' % agora,
        '',
        '- %d partidas por mapa, sementes %d, %d, ... (dano dos inimigos e destino do teletransporte'
        ' são sorteados; a semente torna cada partida reproduzível).' % (n, semente_base + 1, semente_base + 2),
        '- Parâmetros da estratégia: ' + ', '.join('`%s(%s)`' % kv for kv in params.items()) + '.',
        '- Cada partida, uma a uma, está em [resultados.csv](resultados.csv).',
        '',
        '| Mapa | Partidas | Pontuação média | Desvio | Mín | Máx | Ouros (média) | Partidas com 3 ouros'
        ' | Sobreviveu | Ações (média) | Fim da partida |',
        '|---|---|---|---|---|---|---|---|---|---|---|',
    ]
    for mapa, s in por_mapa.items():
        linhas.append('| %s | %d | %.1f | %.1f | %d | %d | %.2f | %d/%d | %d/%d (%.0f%%) | %.1f | %s |' % (
            mapa, s['n'], s['pts_media'], s['pts_desvio'], s['pts_min'], s['pts_max'],
            s['ouros_media'], s['tres_ouros'], s['n'], s['vivos'], s['n'], 100.0 * s['vivos'] / s['n'],
            s['acoes_media'], s['motivos']))
    linhas += [
        '',
        '## Decisão sem o mapa real',
        '',
        '[verifica_decisao.pl](../verifica_decisao.pl) percorre todos os predicados alcançáveis a partir de'
        ' `executa_acao/1` e procura `tile/3`, `adjacentes/1`, `observacoes/1` (e seus auxiliares).',
        '',
    ]
    if proibidos:
        linhas.append('**FALHOU**: a decisão alcança predicados que leem o mapa real:')
        linhas += ['- `%s`' % c for c in proibidos]
    else:
        linhas.append('**OK**: nenhum caminho da decisão chega a esses predicados.')
    linhas.append('')
    pathlib.Path(caminho).write_text('\n'.join(linhas), encoding='utf-8')


def main():
    ap = argparse.ArgumentParser(description='Executa partidas do agente sem interface e registra os resultados.')
    ap.add_argument('-n', type=int, default=30, help='partidas por mapa (padrão 30)')
    ap.add_argument('--mapas', nargs='+', default=MAPAS_PADRAO, help='arquivos de mapa da pasta do projeto')
    ap.add_argument('--semente', type=int, default=0, help='base das sementes (partida i usa base+i)')
    ap.add_argument('--saida', default='testes/resultados', help='pasta dos arquivos gerados')
    args = ap.parse_args()

    os.chdir(PROJETO)
    saida = pathlib.Path(args.saida)
    saida.mkdir(parents=True, exist_ok=True)

    prolog = Prolog()
    prolog.consult('main.pl')
    prolog.consult('testes/verifica_decisao.pl')

    # verificação estática: a decisão não pode chegar ao mapa real
    r = consulta(prolog, 'usos_proibidos(C), maplist(atomic_list_concat_pi, C, T)')
    proibidos = [str(t) for t in r[0]['T']] if r else ['(verificação não executou)']
    print('Decisão sem o mapa real:', 'OK' if not proibidos else 'FALHOU ' + str(proibidos))

    registros, por_mapa = [], {}
    for mapa in args.mapas:
        do_mapa = []
        for i in range(1, args.n + 1):
            reg = joga_partida(prolog, mapa, args.semente + i)
            reg['execucao'] = i
            do_mapa.append(reg)
            print('\r%s: %d/%d' % (mapa, i, args.n), end='', flush=True)
        print()
        registros += do_mapa
        por_mapa[do_mapa[0]['mapa']] = resume(do_mapa)

    with open(saida / 'resultados.csv', 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=CAMPOS)
        w.writeheader()
        for reg in registros:
            w.writerow({k: reg[k] for k in CAMPOS})

    escreve_resumo(saida / 'resumo.md', por_mapa, proibidos, parametros(prolog), args.n, args.semente)

    print()
    print('%-16s %8s %8s %8s %10s %8s  %s' % ('mapa', 'pontos', 'ouros', '3 ouros', 'vivo', 'ações', 'fim'))
    for mapa, s in por_mapa.items():
        print('%-16s %8.1f %8.2f %5d/%-3d %6d/%-3d %8.1f  %s' % (
            mapa, s['pts_media'], s['ouros_media'], s['tres_ouros'], s['n'], s['vivos'], s['n'],
            s['acoes_media'], s['motivos']))
    print('\nArquivos: %s e %s' % (saida / 'resultados.csv', saida / 'resumo.md'))
    return 1 if proibidos else 0


if __name__ == '__main__':
    sys.exit(main())
