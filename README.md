# Kan para Android

Cliente Flutter para a API do [Kan](https://github.com/kanbn/kan) (kan.bn ou self-hosted).

## Como entrar
1. No Kan (navegador): **Configurações > API > Criar API key**.
2. No app: informe o servidor (`https://kan.bn` ou o seu) e cole a API key.

## Funcionalidades
- **Workspaces**: listar, trocar, criar, editar (nome, slug, descrição, início da semana, e-mails visíveis), excluir, buscar.
- **Membros**: convidar por e-mail, link de convite (gerar/copiar/desativar), alterar papel (admin/membro/convidado), remover, aceitar convite.
- **Webhooks**: criar, editar, ativar/desativar, testar, excluir.
- **Quadros**: listar (quadros/templates/arquivados), favoritar, criar (com listas iniciais ou a partir de template), renomear, slug, público/privado, arquivar, mover de workspace, excluir, membros do quadro.
- **Listas**: criar, renomear, reordenar, excluir.
- **Cartões**: criar, arrastar entre listas (toque longo), mover, duplicar, excluir, título, descrição, prazo, etiquetas, membros, filtros (membros/etiquetas/prazo).
- **Checklists**: criar, renomear, excluir; itens: adicionar, marcar, editar, reordenar, excluir.
- **Comentários e atividade**: histórico paginado, comentar, editar/excluir os seus.
- **Anexos**: enviar arquivo, abrir, excluir.
- **Etiquetas**: criar, editar cor/nome, excluir.
- **Perfil**: nome, foto (URL), senha.

## Estrutura
```
lib/
  api/kan_api.dart        cliente REST (todas as rotas)
  models.dart             modelos de dados
  session.dart            servidor + API key salvos
  utils.dart              diálogos, cores, datas, HTML<->texto
  screens/                telas
```
