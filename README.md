# Organizador de tarefas pessoal (método dos 4 baldes)

App web pessoal de organização de tarefas, single-page, deploy no Netlify e persistência no Supabase com login. Uso individual da Giovanna.

## Por que existe

O problema real: alto volume de demandas chegando por vários canais (Slack, WhatsApp, pedidos de liderança), tudo misturado, sem captura confiável e sem priorização. Hoje ela anota tudo em notas soltas no computador e perde o fio.

O app materializa um método específico. **Não mude a lógica dos baldes nem os rituais sem necessidade — eles são a solução, a UI é só o meio.**

## O método (regra de negócio)

Separar três coisas que hoje se misturam: capturar, priorizar, executar.

- **Caixa de captura**: entrada única. Tudo que chega vai pra cá na hora, sem julgar. Bucket `inbox`.
- **4 baldes** (bucket):
  - `hoje` — no máximo 3 tarefas-chave (MITs). A UI mostra contador `x/3` e alerta quando passa de 3.
  - `semana` — tarefas complexas de horizonte semanal.
  - `aguardando` — o que depende de outra pessoa (ela coordena com muita gente; evita cobrança perdida).
  - `depois` — não é agora, mas não perder.
- **Tarefa complexa** nunca fica solta: fica em `semana` e só o próximo passo concreto vai pra `hoje`.
- **Rituais**: diário (10 min, esvaziar captura + escolher MITs + limpar concluídas) e semanal (segunda, zerar captura + revisar aguardando + quebrar as complexas em próximos passos).
- **Regra de priorização** (quando em dúvida): move meta da semana/Feirão? tem prazo real? tem alguém bloqueado esperando? Dois "sim" = hoje, um = semana, nenhum = depois.

## Decisões técnicas (e o que foi descartado)

- **Stack**: HTML/CSS/JS puro, sem build, sem framework. Um arquivo. Supabase JS via CDN.
- **Persistência: Supabase com login (Supabase Auth, e-mail/senha).** Descartadas duas alternativas:
  - `window.storage` de artefato Claude: persiste, mas preso ao ambiente da Claude, sem app próprio.
  - `localStorage` puro: simples, mas um dispositivo só, sem sincronizar note e celular.
  - O login foi escolhido porque é a única opção que entrega o requisito original: acessar de qualquer lugar, sincronizado e privado.
- **Segurança**: a chave `anon` é pública por design. A proteção vem de Auth + Row Level Security (RLS): cada usuário só enxerga as próprias linhas. RLS está no `setup.sql`.
- **UI**: paleta clara com um código de cor por balde (âmbar/hoje, azul/semana, violeta/aguardando, cinza/depois). Sem dependências de fonte externa. Responsivo até mobile.

## Arquivos

- `index.html` — o app inteiro (UI + auth + CRUD Supabase). As chaves ficam em duas constantes no topo do script (`SUPABASE_URL`, `SUPABASE_ANON_KEY`), com placeholders. Se não configuradas, o app mostra uma tela de "falta configurar".
- `view.html` — visão somente-leitura pra compartilhar (ver v2.7 abaixo). Arquivo separado de propósito: zero risco de misturar código autenticado com público.
- `setup.sql` — cria a tabela `tasks` e liga o RLS. Rodar uma vez no SQL Editor do Supabase.
- `README.md` — este arquivo.

## Schema

Tabela `tasks`: `id` (uuid), `user_id` (uuid, default `auth.uid()`, FK pra `auth.users`, on delete cascade), `text` (text), `bucket` (text, default `inbox`), `done` (bool, default false), `created_at` (timestamptz), `area` (text, opcional — tag livre tipo "growth"/"ops"), `urgent` (bool, default false), `due_date` (date, opcional), `waiting_on` (text, opcional — só usado no balde Aguardando), `done_at` (timestamptz, opcional — quando foi marcada concluída), `cleared_at` (timestamptz, opcional — quando foi tirada da vista pelo "limpar concluídas"), `source` (text, opcional — origem da captura, ex. `'slack'`), `parent_id` (uuid, opcional, FK pra `tasks`, on delete cascade — um nível de subtarefa). RLS ligado com policy `for all using (auth.uid() = user_id) with check (...)`. SQL completo no `setup.sql`.

**v2 — priorização leve:** decidido não usar matriz GUT (gravidade/urgência/tendência) por tarefa porque adiciona fricção na captura. Em vez disso: tag de área livre (texto, com sugestão das últimas usadas via `<datalist>`), flag de urgência (🔥) e prazo opcional — todos editados só na hora de organizar a tarefa (no painel que abre ao clicar nela), nunca na captura. Prazo vencido fica destacado em vermelho, prazo de hoje em âmbar. GUT continua útil como pergunta mental no ritual semanal, não como campo salvo.

**v2.1 — captura inteligente:** `"texto | área | até terça"` ou `"texto, urgente, até sexta"` já preenchem área/prazo/urgência na hora de capturar (ver comentário em `smartParse()` no `index.html`).

**v2.2 — ajustes de diagnóstico:** texto da tarefa agora é editável (painel ao clicar), filtro por urgência/atraso/área (incluindo "sem área"), campo "aguardando quem" no balde Aguardando, confirmação antes de deletar, e correções de robustez (flash de sessão em background, parser de datas gulosa, foco do campo de captura, duplo clique).

**v2.3 — auto-promoção e histórico:** tarefa de Esta semana/Aguardando/Depois com `due_date` vencendo hoje ou no passado sobe sozinha pra Hoje ao carregar o app (avisa com um banner). "Limpar concluídas" não apaga mais — só marca `cleared_at` e some da coluna; um painel "Histórico de concluídas" no rodapé mostra tudo que já foi feito, agrupado por dia.

**v2.5 — subtarefas ("próximos passos"):** tarefa pode ter `parent_id` apontando pra outra tarefa — um nível só de aninhamento (uma subtask não pode ter subtask). Cada passo é uma tarefa normal (tem seu próprio balde/área/prazo/urgência, entra em busca/filtro/promoção automática/histórico igual a qualquer outra). No painel de uma tarefa-mãe, um campo "+ adicionar próximo passo" cria o passo direto na `inbox` (capturar não é decidir, vale pra passos também), e uma mini-checklist mostra o progresso ("N/M passos"). Cada passo também aparece como card independente no balde em que estiver, com uma tag "↳ de: ..." apontando pra mãe. Concluir todos os passos **não** fecha a mãe automaticamente — quem decide isso é a Giovanna. Apagar a mãe apaga os passos junto (`on delete cascade`), com aviso específico antes de confirmar.

**v2.7 — visão compartilhada somente-leitura:** um painel "Compartilhar visão" no `index.html` gera um link público (`view.html?t=<token>`) que mostra Hoje/Esta semana/Aguardando + concluídas nos últimos 7 dias, sem exigir login de quem recebe. Arquitetura: tabela `share_tokens` (um token por vez, revogável) + duas funções Postgres `security definer` (`get_shared_tasks`, `is_valid_share_token`) que ignoram o RLS normal só pra essa consulta específica e controlada — nunca expõem a tabela `tasks` inteira. Fora dos baldes citados, nada mais é visível (a Caixa de captura fica de fora de propósito: é pré-triagem, não faz sentido virar público). Segurança é "quem tem o link, vê" (como um link do Trello), não uma conta de verdade — por isso dá pra revogar a qualquer momento e gerar um novo.

## Setup pendente (não feito ainda)

1. Rodar `setup.sql` no SQL Editor do Supabase.
2. Copiar Project URL e chave `anon public` (Project Settings > API).
3. Colar as duas nas constantes do topo de `index.html`.
4. Deploy do `index.html` no Netlify.
5. Criar o login na tela do app e usar.
6. Opcional: desligar "Confirm email" em Authentication > Providers > Email pra login imediato.

## Ideias de próximos passos (não pedidas ainda)

- Ordenação/arrastar dentro do balde e persistir posição (hoje ordena por `created_at`).
- Data de vencimento e um destaque visual pro que vence hoje.
- Realtime do Supabase pra sincronizar entre abas/dispositivos abertos ao mesmo tempo.
- Atalho de captura rápida (PWA + share target no celular) pra jogar nota direto no `inbox`.
- Integração de entrada com as ferramentas dela (Pipedrive/HubSpot/Slack) pra capturar demanda sem digitar.

## Notas

- Sem framework de propósito: mantém leve e fácil de editar. Se for crescer muito, considerar um bundler, mas o requisito é "simples".
- Free tier do Supabase pausa após ~1 semana de inatividade; uso diário evita. Dados persistem na pausa.
