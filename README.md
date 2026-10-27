# Instalador Maturador

Instala o **Maturador de Chip** numa VPS com um comando. É só uma pergunta: o domínio.

## Comando (como root)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/victoreder/instalador-maturador/main/instalar.sh)
```

Rodar de novo **atualiza** o sistema. As respostas e senhas ficam em `/opt/maturador/.env`.

## O que ele faz

1. **Analisa a VPS** e instala do jeito que funciona nela:

   | O que encontrou | Como instala |
   |---|---|
   | VPS zerada | Instala o Docker e sobe o Caddy (HTTPS automático) |
   | Traefik (Portainer, EasyPanel, Coolify, Dokploy...) | Usa o Traefik que já existe (labels ou arquivo de rotas), em stack no Swarm ou compose |
   | Outro proxy nas portas 80/443 (nginx...) | Sobe em portas locais e mostra o que cadastrar no painel |

2. **Pergunta o domínio** (ex.: `suaempresa.com.br`) e se quer os subdomínios padrão: `app.<domínio>` (sistema),
   `s3.<domínio>` (MinIO) e `wpp.<domínio>` (Evolution). Respondendo **não**, escolhe cada um (ex.: `maturador`
   → `maturador.<domínio>`), e todo o resto (rotas, `APP_URL`, S3, Evolution, link final) usa o que foi escolhido.
   Confere se o DNS já aponta para a VPS.
3. **Instala a Evolution API** junto, usando o mesmo Postgres (banco `evolution`) e o mesmo Redis. Ela já entra
   no sistema como servidor de API (variáveis `EVOLUTION_URL`/`EVOLUTION_API_KEY`).
4. **Sobe tudo** em `/opt/maturador/maturador.yml`: sistema, Postgres 17, Redis 7 e MinIO, com senhas e `APP_KEY`
   aleatórias. O S3 também já vai configurado (`S3_*`).
5. No fim mostra o link `https://<endereço>/setup` para criar a conta de dono.

## Requisitos

- Ubuntu/Debian, acesso root, portas 80 e 443 livres (na VPS zerada).
- 2 GB de RAM (4 GB com a Evolution).
- A imagem `ghcr.io/victoreder/maturador-chip` **pública** no GHCR (o Actions do `maturador-chip` publica a cada
  push na `main`).

## Aviso de nova versão

O sistema lê o [`versao.json`](versao.json) deste repositório. Ao publicar uma versão nova da imagem, troque o
número aqui (ex.: `0.1.57`, o mesmo da tag gerada pelo Actions) para os clientes verem o aviso de atualização.
