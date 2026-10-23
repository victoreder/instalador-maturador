#!/usr/bin/env bash

## ============================================================================
## INSTALADOR MATURADOR
## Instala: Maturador de Chip (sistema + telas) com Postgres, Redis, MinIO (S3)
## e Evolution API (WhatsApp), já cadastrada no sistema. Pergunta só o domínio.
##
## Funciona em VPS zerada e em VPS que já tem outro sistema:
##   - VPS zerada ............... Docker + Caddy (HTTPS automático)
##   - Traefik (Portainer, EasyPanel, Coolify, Dokploy...) ... usa o Traefik que já existe
##   - Outro proxy (nginx...) ... sobe sem proxy e mostra o que apontar
##
## COMANDO (como root):
##   bash <(curl -sSL https://raw.githubusercontent.com/victoreder/instalador-maturador/main/instalar.sh)
##
## Rodar de novo atualiza a instalação (as configurações ficam em /opt/maturador).
## ============================================================================

set -uo pipefail

VERSAO="1.0"
DIR="/opt/maturador"
ENV_FILE="$DIR/.env"
PROJETO="maturador"
ATUALIZACAO_URL="https://raw.githubusercontent.com/victoreder/instalador-maturador/main/versao.json"

IMG_APP="ghcr.io/victoreder/maturador-chip:latest"
IMG_POSTGRES="postgres:17-alpine"
IMG_REDIS="redis:7-alpine"
IMG_MINIO="ghcr.io/victoreder/minio:RELEASE.2024-01-13T07-53-03Z"
IMG_EVOLUTION="evoapicloud/evolution-api:latest"
IMG_CADDY="caddy:2-alpine"

amarelo="\e[91m"
verde="\e[92m"
branco="\e[97m"
vermelho="\e[91m"
## Paleta única em vermelho (verde só para ✔)
ciano="\e[91m"
azul="\e[31m"
roxo="\e[31m"
cinza="\e[90m"
negrito="\e[1m"
reset="\e[0m"

## Lê do terminal mesmo quando o script vem por "curl | bash"
TTY=/dev/tty
{ : </dev/tty; } 2>/dev/null || TTY=/dev/stdin

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; printf "\e[?25h"' EXIT

## ============================================================================
## VISUAL (cores, caixas, efeitos)
## ============================================================================

LARGURA=62
NOMES_PASSOS=("Domínio")
TOTAL_PASSOS=${#NOMES_PASSOS[@]}
QUADROS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

info()  { echo -e "  ${ciano}›${reset} $*"; }
ok()    { echo -e "  ${verde}✔${reset} $*"; }
aviso() { echo -e "  ${amarelo}!${reset} ${amarelo}$*${reset}"; }
falha() { echo -e "  ${vermelho}✘ $*${reset}"; }
erro()  { falha "$*"; exit 1; }
dica()  { echo -e "  ${cinza}$*${reset}"; }
texto() { echo -e "  $*"; }

## linha [largura] [caractere]
linha() { local n="${1:-$LARGURA}" c="${2:-─}"; [ "$n" -gt 0 ] && printf "%.0s$c" $(seq 1 "$n"); }

## Efeito de máquina de escrever (desligado fora do terminal ou com SEM_EFEITO=1)
digitar() { # digitar "texto" [cor]
    local t="$1" cor="${2:-}" i
    printf '%b' "$cor"
    if [ -t 1 ] && [ -z "${SEM_EFEITO:-}" ]; then
        for ((i = 0; i < ${#t}; i++)); do
            printf '%s' "${t:i:1}"
            sleep 0.012
        done
    else
        printf '%s' "$t"
    fi
    printf '%b\n' "$reset"
}

banner() {
    clear
    echo ""
    echo -e "\e[91m  ███╗   ███╗ █████╗ ████████╗██╗   ██╗██████╗  █████╗ ██████╗  ██████╗ ██████╗ ${reset}"
    echo -e "\e[91m  ████╗ ████║██╔══██╗╚══██╔══╝██║   ██║██╔══██╗██╔══██╗██╔══██╗██╔═══██╗██╔══██╗${reset}"
    echo -e "\e[91m  ██╔████╔██║███████║   ██║   ██║   ██║██████╔╝███████║██║  ██║██║   ██║██████╔╝${reset}"
    echo -e "\e[91m  ██║╚██╔╝██║██╔══██║   ██║   ██║   ██║██╔══██╗██╔══██║██║  ██║██║   ██║██╔══██╗${reset}"
    echo -e "\e[91m  ██║ ╚═╝ ██║██║  ██║   ██║   ╚██████╔╝██║  ██║██║  ██║██████╔╝╚██████╔╝██║  ██║${reset}"
    echo -e "\e[91m  ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝${reset}"
    echo -e "  ${cinza}$(linha 80 ━)${reset}"
    echo -e "  ${negrito}${branco}Instalador oficial${reset}  ${cinza}•  versão $VERSAO${reset}"
    echo ""
}

## Trilha com os passos: ✔ feitos, ● atual, ○ próximos
trilha() {
    local atual="$1" i n s=""
    for i in "${!NOMES_PASSOS[@]}"; do
        n=$((i + 1))
        if [ "$n" -lt "$atual" ]; then
            s+="${verde}✔ ${NOMES_PASSOS[$i]}${reset}"
        elif [ "$n" -eq "$atual" ]; then
            s+="${negrito}${ciano}● ${NOMES_PASSOS[$i]}${reset}"
        else
            s+="${cinza}○ ${NOMES_PASSOS[$i]}${reset}"
        fi
        [ "$n" -lt "$TOTAL_PASSOS" ] && s+="${cinza} ─ ${reset}"
    done
    echo -e "  $s"
}

## Título em caixa: titulo_caixa "TEXTO" [cor]
titulo_caixa() {
    local cor="${2:-$ciano}"
    echo -e "  ${cor}╭$(linha "$LARGURA")${reset}"
    printf '  %b│%b  ' "$cor" "$reset"
    digitar "$1" "${negrito}${branco}"
    echo -e "  ${cor}╰$(linha "$LARGURA")${reset}"
}

## cabecalho_passo N "Título"
cabecalho_passo() {
    banner
    trilha "$1"
    echo ""
    titulo_caixa "PASSO $1 DE $TOTAL_PASSOS  ·  $2"
    [ "$TOTAL_PASSOS" -gt 1 ] && dica "Digite 0 e aperte Enter para voltar ao passo anterior."
    echo ""
}

## Bloco de informações: abrir_bloco "TÍTULO" [cor] / item "Rótulo" "valor" / fechar_bloco
## Quantidade de caracteres (não de bytes), em qualquer idioma do terminal
tamanho() { printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c; }

## Texto completado com espaços até N caracteres
completar() { local n; n=$(tamanho "$1"); printf '%s%*s' "$1" $(($2 > n ? $2 - n : 0)) ''; }

abrir_bloco() {
    BLOCO_COR="${2:-$roxo}"
    echo -e "  ${BLOCO_COR}┌─ ${negrito}${branco}$1${reset} ${BLOCO_COR}$(linha $((LARGURA - $(tamanho "$1") - 3)))${reset}"
}
item() { printf '  %b│%b  %b%s%b %s\n' "$BLOCO_COR" "$reset" "$cinza" "$(completar "$1" 14)" "$reset" "$2"; }
fechar_bloco() { echo -e "  ${BLOCO_COR}└$(linha "$LARGURA")${reset}"; echo ""; }

## Item já respondido dentro de um passo
feito() { printf '  %b✔%b %b%s%b %s\n' "$verde" "$reset" "$cinza" "$(completar "$1" 18)" "$reset" "$2"; }

## Numeração das instruções: instrucao N "texto"
instrucao() { echo -e "  ${ciano}${negrito}$1${reset}  $2"; }

## girar "mensagem" comando... → roda com animação; saída em $TMP/ultimo.log
girar() {
    local msg="$1" pid rc i=0
    shift
    "$@" >"$TMP/ultimo.log" 2>&1 &
    pid=$!
    printf '\e[?25l'
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b%s%b %s' "$ciano" "${QUADROS[i % 10]}" "$reset" "$msg"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid"
    rc=$?
    printf '\e[?25h'
    if [ "$rc" = 0 ]; then
        printf '\r  %b✔%b %s\e[K\n' "$verde" "$reset" "$msg"
    else
        printf '\r  %b✘%b %s\e[K\n' "$vermelho" "$reset" "$msg"
    fi
    return "$rc"
}

## esperar "mensagem" SEGUNDOS comando... → repete o comando até dar certo (com animação)
esperar() {
    local msg="$1" limite="$2" inicio i=0
    shift 2
    inicio=$SECONDS
    printf '\e[?25l'
    while :; do
        if "$@" >/dev/null 2>&1; then
            printf '\e[?25h\r  %b✔%b %s\e[K\n' "$verde" "$reset" "$msg"
            return 0
        fi
        if [ $((SECONDS - inicio)) -ge "$limite" ]; then
            printf '\e[?25h\r  %b✘%b %s\e[K\n' "$vermelho" "$reset" "$msg"
            return 1
        fi
        local f
        for f in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            printf '\r  %b%s%b %s' "$ciano" "${QUADROS[i % 10]}" "$reset" "$msg"
            i=$((i + 1))
            sleep 0.1
        done
    done
}

## Remove \r, espaços nas pontas e aspas em volta (comum ao copiar e colar)
limpar() {
    local v="$1"
    v="${v//$'\r'/}"
    v="$(printf '%s' "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
    printf '%s' "$v"
}

## perguntar VAR "texto" [padrão] → retorna 1 se a pessoa digitou 0 (voltar)
perguntar() {
    local __var="$1" __texto="$2" __padrao="${3:-}" __v
    while :; do
        if [ -n "$__padrao" ]; then
            printf '%b' "  ${ciano}➜${reset} ${branco}${__texto}${reset} ${cinza}[${__padrao}]${reset}: "
        else
            printf '%b' "  ${ciano}➜${reset} ${branco}${__texto}${reset}: "
        fi
        ler __v
        __v="$(limpar "$__v")"
        [ "$__v" = "0" ] && return 1
        __v="${__v:-$__padrao}"
        [ -n "$__v" ] && break
        aviso "Este campo é obrigatório."
    done
    printf -v "$__var" '%s' "$__v"
}

## sim_nao "pergunta" S|N → 0 = sim, 1 = não, 2 = voltar (0)
sim_nao() {
    local resp padrao="${2:-S}"
    while :; do
        printf '%b' "  ${ciano}➜${reset} ${branco}$1${reset} ${cinza}($([ "$padrao" = S ] && echo 'S/n' || echo 's/N'))${reset}: "
        ler resp
        resp="$(limpar "$resp")"
        [ "$resp" = "0" ] && return 2
        resp="${resp:-$padrao}"
        case "$resp" in
            [sSyY]*) return 0 ;;
            [nN]*) return 1 ;;
        esac
        aviso "Responda S ou N."
    done
}

enter() {
    printf '%b' "  ${cinza}${1:-Aperte Enter para continuar...}${reset}"
    local _r; ler _r
}

## Lê uma linha do terminal; se o terminal fechar, encerra em vez de ficar em loop
ler() {
    IFS= read -r "$1" <"$TTY" || { echo; erro "Entrada encerrada. Rode o setup de novo."; }
}

aleatorio() { head -c "${1:-16}" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

porta_em_uso() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"
    else
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"
    fi
}

porta_livre_a_partir_de() {
    local p="$1"
    while porta_em_uso "$p"; do p=$((p + 1)); done
    echo "$p"
}

ip_da_vps() {
    local ip=""
    for u in https://api.ipify.org https://ifconfig.me https://icanhazip.com; do
        ip="$(curl -fsS4 --max-time 5 "$u" 2>/dev/null | tr -d '[:space:]')"
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { echo "$ip"; return; }
    done
    hostname -I 2>/dev/null | awk '{print $1}'
}

## IPs de um domínio, um por linha. Pergunta primeiro ao servidor DNS oficial do
## domínio e depois ao Google/Cloudflare, para não pegar resposta velha do cache da VPS.
ips_do_dominio() {
    {
        python3 -I - "$1" 2>/dev/null <<'PYEOF'
import json, random, socket, struct, sys, urllib.request

host = sys.argv[1].strip(".").lower()

def doh(nome, tipo):
    """Consulta DNS por HTTPS (Google e Cloudflare). Retorna os dados das respostas do tipo pedido."""
    codigo = {"A": 1, "NS": 2}[tipo]
    saida = []
    for base in ("https://dns.google/resolve", "https://cloudflare-dns.com/dns-query"):
        try:
            req = urllib.request.Request(f"{base}?name={nome}&type={tipo}", headers={"accept": "application/dns-json"})
            dados = json.load(urllib.request.urlopen(req, timeout=5))
        except Exception:
            continue
        for r in dados.get("Answer") or []:
            if r.get("type") == codigo:
                v = r.get("data", "").rstrip(".")
                if v and v not in saida:
                    saida.append(v)
    return saida

def pular_nome(dados, i):
    while True:
        tam = dados[i]
        if tam == 0:
            return i + 1
        if tam & 0xC0 == 0xC0:
            return i + 2
        i += tam + 1

def consulta_direta(ip_ns, nome):
    """Pergunta direto ao servidor DNS oficial do domínio (sem cache no caminho)."""
    tid = random.randint(0, 65535)
    pacote = struct.pack(">HHHHHH", tid, 0, 1, 0, 0, 0)
    for parte in nome.split("."):
        pacote += bytes([len(parte)]) + parte.encode()
    pacote += b"\0" + struct.pack(">HH", 1, 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    try:
        s.sendto(pacote, (ip_ns, 53))
        dados, _ = s.recvfrom(4096)
    finally:
        s.close()
    if struct.unpack(">H", dados[:2])[0] != tid:
        return []
    respostas = struct.unpack(">H", dados[6:8])[0]
    i = pular_nome(dados, 12) + 4
    ips = []
    for _ in range(respostas):
        i = pular_nome(dados, i)
        tipo, _cls, _ttl, tam = struct.unpack(">HHIH", dados[i:i + 10])
        i += 10
        if tipo == 1 and tam == 4:
            ips.append(socket.inet_ntoa(dados[i:i + 4]))
        i += tam
    return ips

ips = []
## 1) Servidor oficial do domínio: acha a zona subindo pelos níveis (app.x.com.br → x.com.br)
partes = host.split(".")
for n in range(len(partes) - 1):
    zona = ".".join(partes[n:])
    servidores = doh(zona, "NS")
    if not servidores:
        continue
    for ns in servidores[:3]:
        for ip_ns in doh(ns, "A")[:1]:
            try:
                ips = consulta_direta(ip_ns, host)
            except Exception:
                ips = []
            if ips:
                break
        if ips:
            break
    break
## 2) DNS públicos (Google e Cloudflare)
for ip in doh(host, "A"):
    if ip not in ips:
        ips.append(ip)
print("\n".join(ips))
PYEOF
        getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}'
    } | awk 'NF && !visto[$0]++'
}

## ============================================================================
## DETECÇÃO DO AMBIENTE DA VPS
## ============================================================================
## Define:
##   MODO_DEPLOY = compose | stack     (docker compose ou docker stack deploy)
##   MODO_ROTA   = caddy | labels | file | manual
##   PAINEL      = nome amigável do que foi encontrado

## Lê a configuração de um Traefik (serviço do Swarm ou container) e imprime
## variáveis TRAEFIK_* para o shell.
analisar_traefik() { # analisar_traefik service|container NOME
    docker "$([ "$1" = service ] && echo service || echo container)" inspect "$2" >"$TMP/traefik.json" 2>/dev/null || return 1
    python3 - "$1" "$TMP/traefik.json" <<'PYEOF'
import json, re, subprocess, sys, os

tipo, arq = sys.argv[1], sys.argv[2]
d = json.load(open(arq))[0]

if tipo == "service":
    cs = d["Spec"]["TaskTemplate"]["ContainerSpec"]
    imagem = cs.get("Image") or ""
    args = (cs.get("Command") or []) + (cs.get("Args") or [])
    mounts = [(m.get("Source"), m.get("Target")) for m in (cs.get("Mounts") or []) if m.get("Type") == "bind"]
    redes = []
    for n in d["Spec"]["TaskTemplate"].get("Networks") or []:
        try:
            nome = subprocess.run(["docker", "network", "inspect", "-f", "{{.Name}}", n["Target"]],
                                  capture_output=True, text=True).stdout.strip()
        except Exception:
            nome = ""
        if nome:
            redes.append(nome)
else:
    imagem = (d.get("Config") or {}).get("Image") or ""
    args = [d.get("Path", "")] + (d.get("Args") or [])
    mounts = [(m.get("Source"), m.get("Destination")) for m in (d.get("Mounts") or []) if m.get("Type") == "bind"]
    redes = list((d.get("NetworkSettings") or {}).get("Networks", {}).keys())

def no_host(caminho):
    """Converte um caminho de dentro do container para o caminho na VPS."""
    melhor = None
    for src, dst in mounts:
        if dst and (caminho == dst or caminho.startswith(dst.rstrip("/") + "/")):
            if melhor is None or len(dst) > len(melhor[1]):
                melhor = (src, dst)
    if not melhor:
        return ""
    return melhor[0] + caminho[len(melhor[1].rstrip("/")):]

a = "\n".join(args)
al = a.lower()

## Arquivo de configuração estática (traefik.yml / .toml)
texto = ""
cfg = re.search(r"--configfile[= ](\S+)", a, re.I)
candidatos = [cfg.group(1)] if cfg else ["/etc/traefik/traefik.yml", "/etc/traefik/traefik.yaml", "/etc/traefik/traefik.toml",
                                         "/traefik.yml", "/traefik.yaml", "/traefik.toml"]
for c in candidatos:
    h = no_host(c)
    if h and os.path.isfile(h):
        texto = open(h, errors="ignore").read()
        break
if not texto and os.path.isdir("/etc/easypanel/traefik"):
    for raiz, _, arquivos in os.walk("/etc/easypanel/traefik"):
        for f in arquivos:
            if f in ("traefik.yml", "traefik.yaml", "traefik.toml", "static.yaml", "static.yml"):
                texto += open(os.path.join(raiz, f), errors="ignore").read() + "\n"
tl = texto.lower()

def primeiro(padroes, s, flags=re.M):
    for p in padroes:
        m = re.search(p, s, flags)
        if m:
            return m.group(1)
    return ""

resolver = primeiro([r"--certificatesresolvers\.([^.=\s]+)\."], a, re.I) or \
    primeiro([r"^\s*certificatesresolvers:\s*\n\s+([A-Za-z0-9_-]+):", r"\[certificatesresolvers\.([A-Za-z0-9_-]+)"], texto, re.M | re.I)

entrada = primeiro([r"--entrypoints\.([^.=\s]+)\.address=[^\s]*:443\b"], a, re.I) or \
    primeiro([r"^\s*([A-Za-z0-9_-]+):\s*\n\s+address:\s*[\"']?[^\"'\n]*:443[\"']?",
              r"\[entrypoints\.([A-Za-z0-9_-]+)\]\s*\n\s*address\s*=\s*\"[^\"]*:443\""], texto, re.M | re.I)

swarm = "--providers.swarm" in al or re.search(r"^\s*swarm:\s*$", tl, re.M) is not None or "[providers.swarm]" in tl
docker = "--providers.docker" in al or re.search(r"^\s*docker:\s*$", tl, re.M) is not None or "[providers.docker]" in tl
rede = primeiro([r"--providers\.(?:swarm|docker)\.network=(\S+)"], a, re.I) or \
    primeiro([r"^\s*network:\s*[\"']?([A-Za-z0-9_.-]+)", r"^\s*network\s*=\s*\"([A-Za-z0-9_.-]+)\""], texto, re.M)
pasta = primeiro([r"--providers\.file\.directory=(\S+)"], a, re.I) or \
    primeiro([r"^\s*directory:\s*[\"']?([^\"'\s]+)", r"^\s*directory\s*=\s*\"([^\"]+)\""], texto, re.M)

if not rede:
    for r in redes:
        if r not in ("ingress", "bridge", "host", "none", "docker_gwbridge"):
            rede = r
            break

def versao_traefik():
    """Versão principal do Traefik: pela tag da imagem ou perguntando ao próprio Traefik."""
    m = re.search(r":v?(\d+)(?:\.|$|@|-)", imagem.split("/")[-1])
    if m:
        return int(m.group(1))
    try:
        if tipo == "service":
            cid = subprocess.run(["docker", "ps", "-q", "-f", f"label=com.docker.swarm.service.name={d['Spec']['Name']}"],
                                 capture_output=True, text=True, timeout=10).stdout.split()
        else:
            cid = [d.get("Id", "")]
        if cid and cid[0]:
            saida = subprocess.run(["docker", "exec", cid[0], "traefik", "version"],
                                   capture_output=True, text=True, timeout=15).stdout
            m = re.search(r"Version:\s*v?(\d+)\.", saida)
            if m:
                return int(m.group(1))
    except Exception:
        pass
    return 0

## Traefik v2 não tem o provedor "swarm" (Swarm é o docker com swarmMode): com a label
## traefik.swarm.network ele recusa as labels e ignora o serviço inteiro (404)
if versao_traefik() == 2:
    swarm = False

if swarm:
    rota, label = "labels", "traefik.swarm.network"
elif docker:
    rota, label = "labels", "traefik.docker.network"
elif pasta:
    rota, label = "file", ""
else:
    ## Sem nada declarado: o padrão do Traefik em Swarm (v3) ou container
    rota = "labels"
    label = "traefik.swarm.network" if tipo == "service" and versao_traefik() != 2 else "traefik.docker.network"

pasta_host = no_host(pasta) if pasta else ""

def seguro(v):
    return re.sub(r"[^A-Za-z0-9_.:/@-]", "", v or "")

print(f"TRAEFIK_RESOLVER='{seguro(resolver)}'")
print(f"TRAEFIK_ENTRYPOINT='{seguro(entrada) or 'websecure'}'")
print(f"TRAEFIK_REDE='{seguro(rede)}'")
print(f"TRAEFIK_LABEL_REDE='{seguro(label)}'")
print(f"TRAEFIK_PASTA_ARQUIVOS='{seguro(pasta_host)}'")
print(f"TRAEFIK_ROTA='{rota}'")
PYEOF
}

detectar_ambiente() {
    MODO_DEPLOY="compose"
    MODO_ROTA="caddy"
    PAINEL="VPS zerada"
    TRAEFIK_RESOLVER=""; TRAEFIK_ENTRYPOINT=""; TRAEFIK_REDE=""; TRAEFIK_LABEL_REDE=""
    TRAEFIK_PASTA_ARQUIVOS=""; TRAEFIK_ROTA=""

    local tem_docker=0 alvo="" tipo=""
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && tem_docker=1

    if [ "$tem_docker" = 1 ]; then
        ## Traefik rodando como serviço do Swarm?
        alvo="$(docker service ls --format '{{.Name}} {{.Image}}' 2>/dev/null | awk 'tolower($2) ~ /traefik/ {print $1; exit}')"
        if [ -n "$alvo" ]; then
            tipo="service"
        else
            alvo="$(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | awk 'tolower($2) ~ /traefik/ && $1 !~ /^maturador/ {print $1; exit}')"
            [ -n "$alvo" ] && tipo="container"
        fi
    fi

    ## Nome do painel (só para mostrar)
    local nome=""
    if [ -d /etc/easypanel ] || { [ "$tem_docker" = 1 ] && docker service ls --format '{{.Name}}' 2>/dev/null | grep -qi easypanel; }; then
        nome="EasyPanel"
    elif [ -d /data/coolify ]; then
        nome="Coolify"
    elif [ -d /etc/dokploy ]; then
        nome="Dokploy"
    elif [ "$tem_docker" = 1 ] && docker ps --format '{{.Image}}' 2>/dev/null | grep -qi portainer; then
        nome="Portainer"
    fi

    if [ -n "$tipo" ]; then
        local saida
        if saida="$(analisar_traefik "$tipo" "$alvo")"; then
            eval "$saida"
        fi
        if [ -z "$TRAEFIK_REDE" ] || { [ "$TRAEFIK_ROTA" = file ] && [ -z "$TRAEFIK_PASTA_ARQUIVOS" ]; }; then
            MODO_ROTA="manual"
        else
            MODO_ROTA="$TRAEFIK_ROTA"
        fi
        [ "$tipo" = service ] && MODO_DEPLOY="stack" || MODO_DEPLOY="compose"
        ## Container comum não entra em rede overlay que não é "attachable": usa stack nesse caso
        if [ "$MODO_DEPLOY" = compose ] && [ -n "$TRAEFIK_REDE" ] \
            && [ "$(docker network inspect -f '{{.Driver}} {{.Attachable}}' "$TRAEFIK_REDE" 2>/dev/null)" = "overlay false" ]; then
            MODO_DEPLOY="stack"
        fi
        PAINEL="${nome:-Traefik}"
        return
    fi

    if porta_em_uso 80 || porta_em_uso 443; then
        MODO_ROTA="manual"
        MODO_DEPLOY="compose"
        local quem=""
        quem="$(ss -ltnpH 2>/dev/null | grep -E '[:.](80|443) ' | sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | head -1)"
        [ "$quem" = "docker-proxy" ] && quem=""
        PAINEL="${nome:-${quem:-outro painel}}"
        return
    fi

    [ -n "$nome" ] && PAINEL="$nome"
}

descrever_ambiente() {
    ok "Ambiente detectado: ${negrito}$PAINEL${reset}"
}


## ============================================================================
## ASSISTENTE (PERGUNTAS)
## ============================================================================

## Deixa só o domínio: tira http(s)://, www., caminho, porta, espaços e ponto no fim
## Ex.: "HTTPS://www.Maturador.SuaEmpresa.com.br/login" → "maturador.suaempresa.com.br"
normalizar_dominio() {
    local d
    d="$(limpar "$1")"
    d="${d,,}"
    d="${d// /}"
    d="$(printf '%s' "$d" | sed -E 's#^[a-z]+:/*##; s#^[^@/]*@##; s#[/?\#].*$##; s#:[0-9]*$##; s#\.+$##; s#^(www\.)+##')"
    printf '%s' "$d"
}

## Endereços que o sistema usa
enderecos() {
    echo "$APP_HOST"
    echo "$S3_HOST"
    echo "$EVO_HOST"
}

## ---------------------------------------------------------------- Passo 1: domínio
passo_dominio() {
    local d
    while :; do
        cabecalho_passo 1 "DOMÍNIO"
        texto "Qual é o domínio da sua empresa?"
        dica "Exemplo: suaempresa.com.br  (sem https:// e sem www)"
        echo ""
        perguntar d "Domínio" "${DOMINIO:-}" || return 1
        DOMINIO="$(normalizar_dominio "$d")"
        [ "$DOMINIO" != "$(limpar "$d")" ] && dica "  Ajustei para: $DOMINIO"
        if ! [[ "$DOMINIO" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
            falha "Domínio inválido: $DOMINIO"
            enter
            continue
        fi
        APP_HOST="maturador.$DOMINIO"
        S3_HOST="s3.$DOMINIO"
        EVO_HOST="evo.$DOMINIO"
        echo ""
        abrir_bloco "ENDEREÇOS QUE PRECISAM APONTAR PARA ESTA VPS" "$azul"
        item "Sistema" "$APP_HOST"
        item "Arquivos" "$S3_HOST"
        item "WhatsApp" "$EVO_HOST"
        fechar_bloco
        verificar_dns && return 0
    done
}

## Retorna 0 = DNS ok (ou seguir mesmo assim), 1 = voltar e corrigir o domínio
verificar_dns() {
    local ip_vps tudo_ok resp h ip ips
    ip_vps="$(ip_da_vps)"
    while :; do
        info "Conferindo se os endereços já apontam para esta VPS ${cinza}(${ip_vps:-IP desconhecido})${reset}..."
        tudo_ok=1
        while read -r h; do
            ips="$(ips_do_dominio "$h")"
            if [ -n "$ips" ] && { [ -z "$ip_vps" ] || printf '%s\n' "$ips" | grep -qxF "$ip_vps"; }; then
                echo -e "    ${verde}✔${reset} $h"
            else
                ip="$(printf '%s\n' "$ips" | head -1)"
                echo -e "    ${vermelho}✘${reset} $h ${cinza}→ ${ip:-não encontrado}${reset}"
                tudo_ok=0
            fi
        done < <(enderecos)
        [ "$tudo_ok" = 1 ] && { echo ""; ok "Tudo certo com os endereços!"; sleep 1; return 0; }
        echo ""
        abrir_bloco "COMO APONTAR" "$amarelo"
        item "Onde" "no painel do seu domínio (Registro.br, Cloudflare, Hostinger...)"
        item "Tipo" "A"
        item "Nome" "cada endereço com ✘"
        item "Valor" "${ip_vps:-o IP desta VPS}"
        fechar_bloco
        dica "Usa Cloudflare? Deixe a nuvem cinza (\"somente DNS\"). Pode levar alguns minutos para valer."
        echo ""
        printf '%b' "  ${branco}Enter${reset} conferir de novo  ${cinza}•${reset}  ${branco}C${reset} continuar assim  ${cinza}•${reset}  ${branco}0${reset} corrigir o domínio: "
        ler resp
        resp="$(limpar "$resp")"
        case "$resp" in
            0) return 1 ;;
            [cC]*) aviso "Sem o apontamento certo o sistema não abre. Corrija assim que puder."; sleep 2; return 0 ;;
        esac
        echo ""
    done
}

assistente() {
    local passos=(passo_dominio)
    local i
    while :; do
        i=0
        while [ $i -lt ${#passos[@]} ]; do
            if ${passos[$i]}; then
                i=$((i + 1))
            else
                [ $i -gt 0 ] && i=$((i - 1))
            fi
        done

        banner
        trilha $((TOTAL_PASSOS + 1))
        echo ""
        titulo_caixa "CONFIRA OS DADOS"
        echo ""
        abrir_bloco "O QUE VAI SER INSTALADO" "$azul"
        item "Sistema" "https://$APP_HOST"
        item "Arquivos" "https://$S3_HOST"
        item "WhatsApp" "https://$EVO_HOST  (Evolution API)"
        item "Ambiente" "$PAINEL"
        fechar_bloco
        sim_nao "Está tudo certo? S = instalar  •  N = corrigir" S && return 0
        dica "Vamos refazer. Aperte Enter nas respostas que já estão certas."
        sleep 2
    done
}

## ============================================================================
## PREPARAÇÃO DA VPS
## ============================================================================

verificacoes_iniciais() {
    [ "$(id -u)" -eq 0 ] || erro "Rode como root (sudo -i) e tente de novo."
    command -v curl >/dev/null 2>&1 || {
        command -v apt-get >/dev/null 2>&1 || erro "Instale o curl e rode de novo."
        apt-get update -qq && apt-get install -y -qq curl ca-certificates >/dev/null
    }
    if ! command -v python3 >/dev/null 2>&1; then
        command -v apt-get >/dev/null 2>&1 || erro "Instale o python3 e rode de novo."
        apt-get update -qq && apt-get install -y -qq python3 >/dev/null
    fi
    local ram
    ram="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"
    if [ -n "$ram" ] && [ "$ram" -lt 1800 ]; then
        aviso "Esta VPS tem ${ram}MB de memória. O recomendado é 2GB ou mais (4GB com a Evolution)."
        sleep 2
    fi
}

instalar_docker_agora() {
    apt-get update -qq || return 1
    timedatectl set-timezone America/Sao_Paulo 2>/dev/null || true
    curl -fsSL https://get.docker.com | sh
}

instalar_compose_agora() {
    apt-get update -qq || return 1
    apt-get install -y -qq docker-compose-plugin || apt-get install -y -qq docker-compose-v2
}

instalar_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        command -v apt-get >/dev/null 2>&1 || erro "Não encontrei o apt-get. Instale o Docker e rode de novo."
        girar "Preparando a VPS (pode levar alguns minutos)" instalar_docker_agora || erro "Não consegui preparar a VPS (instalação do Docker)."
    fi
    systemctl enable --now docker >/dev/null 2>&1 || true
    if [ "$MODO_DEPLOY" = compose ] && ! docker compose version >/dev/null 2>&1; then
        girar "Instalando componentes" instalar_compose_agora || erro "Não consegui instalar o Docker Compose."
    fi
    docker info >/dev/null 2>&1 || erro "O Docker não está rodando."
}

## ============================================================================
## CONFIGURAÇÃO SALVA (/opt/maturador/.env)
## ============================================================================

VARS_SALVAS=(MODO_DEPLOY MODO_ROTA PAINEL TRAEFIK_RESOLVER TRAEFIK_ENTRYPOINT TRAEFIK_REDE TRAEFIK_LABEL_REDE
    TRAEFIK_PASTA_ARQUIVOS PORTA_APP PORTA_EVO PORTA_S3 DOMINIO APP_HOST S3_HOST EVO_HOST COM_EVOLUTION
    APP_KEY POSTGRES_PASSWORD MINIO_ROOT_USER MINIO_ROOT_PASSWORD EVOLUTION_API_KEY)

salvar_config() {
    mkdir -p "$DIR"
    local v
    {
        echo "## Maturador — configuração do instalador v$VERSAO ($(date '+%d/%m/%Y %H:%M'))"
        echo "## Não troque APP_KEY nem as senhas: o sistema deixa de ler o que já foi gravado."
        for v in "${VARS_SALVAS[@]}"; do
            printf "%s='%s'\n" "$v" "${!v:-}"
        done
    } >"$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

carregar_config() {
    # shellcheck disable=SC1090
    . "$ENV_FILE"
}

gerar_segredos() {
    APP_KEY="${APP_KEY:-$(aleatorio 32)}"
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(aleatorio 16)}"
    MINIO_ROOT_USER="${MINIO_ROOT_USER:-maturador}"
    MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(aleatorio 16)}"
    [ "$COM_EVOLUTION" = 1 ] && EVOLUTION_API_KEY="${EVOLUTION_API_KEY:-$(aleatorio 16)}"
    if [ "$MODO_ROTA" = manual ]; then
        PORTA_APP="${PORTA_APP:-$(porta_livre_a_partir_de 3100)}"
        PORTA_S3="${PORTA_S3:-$(porta_livre_a_partir_de 9100)}"
        [ "$COM_EVOLUTION" = 1 ] && PORTA_EVO="${PORTA_EVO:-$(porta_livre_a_partir_de 8180)}"
    fi
    return 0
}

## ============================================================================
## ARQUIVOS DE DEPLOY
## ============================================================================

## Nome do serviço como o proxy enxerga (stack prefixa com o nome da stack)
nome_dns() { [ "$MODO_DEPLOY" = stack ] && echo "${PROJETO}_$1" || echo "$1"; }

labels_traefik() { # labels_traefik ROUTER HOST PORTA INDENT
    local n="$1" h="$2" p="$3" ind="$4"
    printf '%s- traefik.enable=true\n' "$ind"
    printf '%s- traefik.http.routers.%s.rule=Host(`%s`)\n' "$ind" "$n" "$h"
    printf '%s- traefik.http.routers.%s.entrypoints=%s\n' "$ind" "$n" "$TRAEFIK_ENTRYPOINT"
    printf '%s- traefik.http.routers.%s.tls=true\n' "$ind" "$n"
    [ -n "$TRAEFIK_RESOLVER" ] && printf '%s- traefik.http.routers.%s.tls.certresolver=%s\n' "$ind" "$n" "$TRAEFIK_RESOLVER"
    printf '%s- traefik.http.routers.%s.service=%s\n' "$ind" "$n" "$n"
    printf '%s- traefik.http.services.%s.loadbalancer.server.port=%s\n' "$ind" "$n" "$p"
    printf '%s- traefik.http.services.%s.loadbalancer.passhostheader=true\n' "$ind" "$n"
    [ -n "$TRAEFIK_LABEL_REDE" ] && printf '%s- %s=%s\n' "$ind" "$TRAEFIK_LABEL_REDE" "$TRAEFIK_REDE"
    return 0
}

## Bloco final de cada serviço: redes, portas, labels e deploy/restart.
## extras PUBLICO(0|1) [ROUTER HOST PORTA PORTA_LOCAL] [MEMORIA]
extras() {
    local publico="$1" router="${2:-}" host="${3:-}" porta="${4:-}" porta_local="${5:-}" mem="${6:-512M}"
    echo "    networks:"
    echo "      - interna"
    if [ "$publico" = 1 ] && { [ "$MODO_ROTA" = labels ] || [ "$MODO_ROTA" = file ]; }; then
        echo "      - proxy"
    fi
    if [ "$publico" = 1 ] && [ "$MODO_ROTA" = manual ] && [ -n "$porta_local" ]; then
        echo "    ports:"
        if [ "$MODO_DEPLOY" = stack ]; then
            echo "      - { target: $porta, published: $porta_local, mode: host }"
        else
            echo "      - \"127.0.0.1:$porta_local:$porta\""
        fi
    fi
    if [ "$MODO_DEPLOY" = stack ]; then
        echo "    deploy:"
        echo "      placement:"
        echo "        constraints:"
        echo "          - node.role == manager"
        echo "      resources:"
        echo "        limits:"
        echo "          memory: $mem"
        echo "      restart_policy:"
        echo "        condition: any"
        echo "        delay: 5s"
        if [ "$publico" = 1 ] && [ "$MODO_ROTA" = labels ]; then
            echo "      labels:"
            labels_traefik "$router" "$host" "$porta" "        "
        fi
    else
        echo "    restart: unless-stopped"
        echo "    logging: *log"
        if [ "$publico" = 1 ] && [ "$MODO_ROTA" = labels ]; then
            echo "    labels:"
            labels_traefik "$router" "$host" "$porta" "      "
        fi
    fi
}

gerar_arquivo_deploy() {
    local f="$DIR/$PROJETO.yml"
    mkdir -p "$DIR"
    {
        if [ "$MODO_DEPLOY" = stack ]; then
            echo 'version: "3.7"'
        else
            echo "name: $PROJETO"
            echo ""
            echo "x-log: &log"
            echo "  driver: json-file"
            echo "  options: { max-size: \"20m\", max-file: \"3\" }"
        fi
        cat <<EOF

## Gerado pelo instalador Maturador v$VERSAO — para mudar, rode o instalador de novo.
services:

## --------------------------- MATURADOR --------------------------- ##

  maturador-app:
    image: $IMG_APP
    environment:
      NODE_ENV: "production"
      TZ: "America/Sao_Paulo"
      APP_URL: "https://$APP_HOST"
      APP_KEY: "$APP_KEY"
      DATABASE_URL: "postgres://maturador:$POSTGRES_PASSWORD@maturador-postgres:5432/maturador"
      REDIS_URL: "redis://maturador-redis:6379"
      S3_ENDPOINT: "http://maturador-minio:9000"
      S3_URL_PUBLICA: "https://$S3_HOST"
      S3_ACCESS_KEY: "$MINIO_ROOT_USER"
      S3_SECRET_KEY: "$MINIO_ROOT_PASSWORD"
      ATUALIZACAO_URL: "$ATUALIZACAO_URL"
EOF
        if [ "$COM_EVOLUTION" = 1 ]; then
            echo "      EVOLUTION_URL: \"https://$EVO_HOST\""
            echo "      EVOLUTION_API_KEY: \"$EVOLUTION_API_KEY\""
        fi
        [ "$MODO_DEPLOY" = compose ] && echo "    depends_on: [maturador-postgres, maturador-redis, maturador-minio]"
        extras 1 maturador_app "$APP_HOST" 3000 "${PORTA_APP:-}" 1024M

        cat <<EOF

  maturador-postgres:
    image: $IMG_POSTGRES
    command: ["postgres", "-c", "max_connections=200", "-c", "shared_buffers=128MB", "-c", "timezone=America/Sao_Paulo"]
    environment:
      POSTGRES_USER: "maturador"
      POSTGRES_PASSWORD: "$POSTGRES_PASSWORD"
      POSTGRES_DB: "maturador"
      TZ: "America/Sao_Paulo"
    volumes:
      - postgres_data:/var/lib/postgresql/data
EOF
        extras 0 "" "" "" "" 1024M

        ## Sem limite de memória com descarte: as filas (BullMQ) não podem perder chaves
        cat <<EOF

  maturador-redis:
    image: $IMG_REDIS
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - redis_data:/data
EOF
        extras 0 "" "" "" "" 512M

        cat <<EOF

## --------------------------- MINIO (S3) --------------------------- ##

  maturador-minio:
    image: $IMG_MINIO
    command: ["server", "/data"]
    environment:
      MINIO_ROOT_USER: "$MINIO_ROOT_USER"
      MINIO_ROOT_PASSWORD: "$MINIO_ROOT_PASSWORD"
      MINIO_SERVER_URL: "https://$S3_HOST"
      MINIO_BROWSER: "off"
    volumes:
      - minio_data:/data
EOF
        extras 1 maturador_s3 "$S3_HOST" 9000 "${PORTA_S3:-}" 512M

        if [ "$COM_EVOLUTION" = 1 ]; then
        ## Usa o mesmo Postgres (banco "evolution") e o mesmo Redis (db 1)
        cat <<EOF

## --------------------------- EVOLUTION API --------------------------- ##

  maturador-evolution:
    image: $IMG_EVOLUTION
    volumes:
      - evolution_instances:/evolution/instances
    environment:
      SERVER_URL: "https://$EVO_HOST"
      AUTHENTICATION_API_KEY: "$EVOLUTION_API_KEY"
      AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES: "true"
      DEL_INSTANCE: "false"
      LANGUAGE: "pt-BR"
      CONFIG_SESSION_PHONE_CLIENT: "Maturador"
      CONFIG_SESSION_PHONE_NAME: "Chrome"
      DATABASE_ENABLED: "true"
      DATABASE_PROVIDER: "postgresql"
      DATABASE_CONNECTION_URI: "postgresql://maturador:$POSTGRES_PASSWORD@maturador-postgres:5432/evolution"
      DATABASE_CONNECTION_CLIENT_NAME: "evolution"
      DATABASE_SAVE_DATA_INSTANCE: "true"
      DATABASE_SAVE_DATA_NEW_MESSAGE: "false"
      DATABASE_SAVE_MESSAGE_UPDATE: "false"
      DATABASE_SAVE_DATA_CONTACTS: "false"
      DATABASE_SAVE_DATA_CHATS: "false"
      DATABASE_SAVE_DATA_LABELS: "false"
      DATABASE_SAVE_DATA_HISTORIC: "false"
      CACHE_REDIS_ENABLED: "true"
      CACHE_REDIS_URI: "redis://maturador-redis:6379/1"
      CACHE_REDIS_PREFIX_KEY: "evolution"
      CACHE_REDIS_SAVE_INSTANCES: "false"
      CACHE_LOCAL_ENABLED: "false"
      S3_ENABLED: "false"
      TELEMETRY: "false"
      WEBSOCKET_ENABLED: "false"
      RABBITMQ_ENABLED: "false"
      SQS_ENABLED: "false"
      WEBHOOK_GLOBAL_ENABLED: "false"
      WEBHOOK_REQUEST_TIMEOUT_MS: "60000"
      WEBHOOK_RETRY_MAX_ATTEMPTS: "10"
      WEBHOOK_RETRY_INITIAL_DELAY_SECONDS: "5"
      WEBHOOK_RETRY_USE_EXPONENTIAL_BACKOFF: "true"
      PROVIDER_ENABLED: "false"
EOF
        [ "$MODO_DEPLOY" = compose ] && echo "    depends_on: [maturador-postgres, maturador-redis]"
        extras 1 maturador_evolution "$EVO_HOST" 8080 "${PORTA_EVO:-}" 1024M
        fi

        if [ "$MODO_ROTA" = caddy ]; then
            cat <<EOF

## --------------------------- CADDY (HTTPS automático) --------------------------- ##

  caddy:
    image: $IMG_CADDY
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
EOF
            extras 0 "" "" "" "" 256M
        fi

        echo ""
        echo "volumes:"
        echo "  postgres_data:"
        echo "  redis_data:"
        echo "  minio_data:"
        [ "$COM_EVOLUTION" = 1 ] && echo "  evolution_instances:"
        if [ "$MODO_ROTA" = caddy ]; then
            echo "  caddy_data:"
            echo "  caddy_config:"
        fi
        echo ""
        echo "networks:"
        echo "  interna:"
        if [ "$MODO_DEPLOY" = stack ]; then
            echo "    driver: overlay"
        else
            echo "    name: maturador_rede"
        fi
        if [ "$MODO_ROTA" = labels ] || [ "$MODO_ROTA" = file ]; then
            echo "  proxy:"
            echo "    external: true"
            echo "    name: $TRAEFIK_REDE"
        fi
    } >"$f"
    chmod 600 "$f"

    if [ "$MODO_ROTA" = caddy ]; then
        {
            printf '%s {\n    encode zstd gzip\n    reverse_proxy maturador-app:3000\n}\n' "$APP_HOST"
            printf '\n%s {\n    reverse_proxy maturador-minio:9000\n}\n' "$S3_HOST"
            [ "$COM_EVOLUTION" = 1 ] && printf '\n%s {\n    reverse_proxy maturador-evolution:8080\n}\n' "$EVO_HOST"
        } >"$DIR/Caddyfile"
    fi

    if [ "$MODO_ROTA" = file ]; then
        local r rotas=("maturador_app $APP_HOST $(nome_dns maturador-app):3000" "maturador_s3 $S3_HOST $(nome_dns maturador-minio):9000")
        [ "$COM_EVOLUTION" = 1 ] && rotas+=("maturador_evolution $EVO_HOST $(nome_dns maturador-evolution):8080")
        {
            echo "## Gerado pelo instalador Maturador v$VERSAO"
            echo "http:"
            echo "  routers:"
            for r in "${rotas[@]}"; do
                set -- $r
                echo "    $1:"
                echo "      rule: \"Host(\`$2\`)\""
                echo "      entryPoints: [\"$TRAEFIK_ENTRYPOINT\"]"
                echo "      service: $1"
                if [ -n "$TRAEFIK_RESOLVER" ]; then
                    echo "      tls:"
                    echo "        certResolver: $TRAEFIK_RESOLVER"
                else
                    echo "      tls: {}"
                fi
            done
            echo "  services:"
            for r in "${rotas[@]}"; do
                set -- $r
                echo "    $1:"
                echo "      loadBalancer:"
                echo "        servers: [{ url: \"http://$3\" }]"
            done
        } >"$TRAEFIK_PASTA_ARQUIVOS/maturador-rotas.yml"
    fi
}

## ============================================================================
## SUBIR / ATUALIZAR
## ============================================================================

## ID do container de um serviço (compose ou stack)
container_de() {
    if [ "$MODO_DEPLOY" = stack ]; then
        docker ps -q -f "label=com.docker.swarm.service.name=${PROJETO}_$1" | head -1
    else
        docker ps -q -f "label=com.docker.compose.project=$PROJETO" -f "label=com.docker.compose.service=$1" | head -1
    fi
}

baixar_imagens_stack() {
    local img imgs=("$IMG_APP" "$IMG_POSTGRES" "$IMG_REDIS" "$IMG_MINIO")
    [ "$COM_EVOLUTION" = 1 ] && imgs+=("$IMG_EVOLUTION")
    [ "$MODO_ROTA" = caddy ] && imgs+=("$IMG_CADDY")
    for img in "${imgs[@]}"; do
        docker pull -q "$img" || return 1
    done
}

## A imagem do sistema precisa estar pública no GHCR
erro_download() {
    tail -5 "$TMP/ultimo.log"
    grep -qiE "denied|unauthorized" "$TMP/ultimo.log" \
        && erro "Acesso negado ao baixar o sistema. Avise o suporte: a imagem precisa estar liberada."
    erro "Não consegui baixar o sistema. Confira a internet da VPS."
}

subir() {
    cd "$DIR" || erro "Pasta $DIR não encontrada."
    if [ "$MODO_DEPLOY" = stack ]; then
        girar "Baixando o sistema (pode levar alguns minutos)" baixar_imagens_stack || erro_download
        girar "Iniciando os serviços" docker stack deploy --prune --resolve-image always -c "$PROJETO.yml" "$PROJETO" \
            || { tail -5 "$TMP/ultimo.log"; erro "Falha ao iniciar. Arquivo: $DIR/$PROJETO.yml"; }
    else
        girar "Baixando o sistema (pode levar alguns minutos)" docker compose -f "$PROJETO.yml" pull -q || erro_download
        girar "Iniciando os serviços" docker compose -f "$PROJETO.yml" up -d --remove-orphans \
            || { tail -5 "$TMP/ultimo.log"; erro "Falha ao iniciar. Arquivo: $DIR/$PROJETO.yml"; }
    fi
}

banco_pronto() {
    local cid
    cid="$(container_de maturador-postgres)"
    [ -n "$cid" ] && docker exec "$cid" pg_isready -U maturador -d maturador
}

## A Evolution usa um banco próprio ("evolution") no mesmo Postgres
preparar_banco_evolution() {
    [ "$COM_EVOLUTION" = 1 ] || return 0
    esperar "Preparando o banco de dados" 180 banco_pronto \
        || { falha "O banco de dados não respondeu."; return 1; }
    local cid
    cid="$(container_de maturador-postgres)"
    docker exec "$cid" psql -U maturador -d maturador -tAc "select 1 from pg_database where datname = 'evolution'" 2>/dev/null | grep -q 1 \
        && return 0
    docker exec "$cid" createdb -U maturador evolution >/dev/null 2>&1 \
        || { falha "Não consegui criar o banco da Evolution."; return 1; }
    ## Banco novo: reinicia a Evolution para ela não ficar esperando o banco que não existia
    if [ "$MODO_DEPLOY" = stack ]; then
        docker service update --force -q "${PROJETO}_maturador-evolution" >/dev/null 2>&1 || true
    else
        docker compose -f "$DIR/$PROJETO.yml" restart maturador-evolution >/dev/null 2>&1 || true
    fi
}

sistema_respondendo() {
    local cid estado
    cid="$(container_de maturador-app)"
    [ -n "$cid" ] || return 1
    estado="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null)"
    [ "$estado" = healthy ] || docker exec "$cid" wget -qO- http://127.0.0.1:3000/health
}

aguardar_sistema() {
    esperar "Ligando o sistema (até 5 minutos)" 300 sistema_respondendo && return 0
    echo ""
    falha "O sistema não respondeu. Últimas linhas do log:"
    if [ "$MODO_DEPLOY" = stack ]; then
        docker service logs --tail 30 "${PROJETO}_maturador-app" 2>&1 | tail -30
    else
        docker compose -f "$DIR/$PROJETO.yml" logs --tail 30 maturador-app 2>&1 | tail -30
    fi
    echo ""
    aviso "Depois de corrigir, rode o instalador de novo."
    return 1
}

https_respondendo() {
    [ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$APP_HOST:443:127.0.0.1" "https://$APP_HOST/health")" = 200 ]
}

verificar_https() {
    [ "$MODO_ROTA" = manual ] && return 0
    esperar "Liberando o acesso em https://$APP_HOST" 150 https_respondendo && return 0
    aviso "O endereço ainda não abriu. Confira o apontamento do domínio."
    aviso "O cadeado (HTTPS) pode levar alguns minutos para sair."
    return 1
}

## ============================================================================
## RESUMO FINAL
## ============================================================================

resumo_final() {
    banner
    titulo_caixa "🎉  INSTALAÇÃO CONCLUÍDA!"
    echo ""
    abrir_bloco "ACESSE SEU SISTEMA" "$azul"
    item "Endereço" "https://$APP_HOST/setup"
    item "Primeiro acesso" "crie a sua conta de dono nesse link"
    fechar_bloco
    if [ "$COM_EVOLUTION" = 1 ]; then
        abrir_bloco "WHATSAPP (EVOLUTION API)" "$roxo"
        item "Endereço" "https://$EVO_HOST"
        item "Manager" "https://$EVO_HOST/manager"
        item "API Key" "$EVOLUTION_API_KEY"
        item "No sistema" "já cadastrada em Servidores de API"
        fechar_bloco
    else
        abrir_bloco "WHATSAPP" "$roxo"
        item "Próximo passo" "cadastre a sua Evolution ou UazAPI em Servidores de API"
        fechar_bloco
    fi
    if [ "$MODO_ROTA" = manual ]; then
        abrir_bloco "FALTA UM PASSO: CADASTRE OS ENDEREÇOS NO SEU PAINEL (COM HTTPS)" "$amarelo"
        item "$APP_HOST" "→ http://127.0.0.1:$PORTA_APP"
        item "$S3_HOST" "→ http://127.0.0.1:$PORTA_S3"
        [ "$COM_EVOLUTION" = 1 ] && item "$EVO_HOST" "→ http://127.0.0.1:$PORTA_EVO"
        fechar_bloco
    fi
    dica "Configurações e senhas: $ENV_FILE"
    dica "Para atualizar: rode o mesmo comando de instalação e confirme com S."
    echo ""
}

## ============================================================================
## FLUXOS
## ============================================================================

cabecalho_instalacao() {
    banner
    trilha $((TOTAL_PASSOS + 1))
    echo ""
    titulo_caixa "INSTALANDO SEU SISTEMA" "$roxo"
    dica "Pode levar alguns minutos. Não feche esta janela."
    echo ""
}

instalar() {
    gerar_segredos
    salvar_config
    gerar_arquivo_deploy
    subir
    preparar_banco_evolution
    aguardar_sistema
    verificar_https
    resumo_final
}

menu_instalacao_existente() {
    carregar_config
    ## A Evolution vai sempre junto (instalações antigas sem ela ganham na atualização)
    COM_EVOLUTION=1
    EVO_HOST="${EVO_HOST:-evo.${DOMINIO:-${APP_HOST#*.}}}"
    ## Instalação que parou no meio (ex.: sem internet): continua com as mesmas respostas e senhas
    if ! command -v docker >/dev/null 2>&1 || [ -z "$(container_de maturador-app 2>/dev/null)" ]; then
        banner
        titulo_caixa "VAMOS CONTINUAR A INSTALAÇÃO"
        dica "https://${APP_HOST:-?}  •  as respostas anteriores foram mantidas"
        echo ""
        ## N = responder de novo (as senhas geradas continuam as mesmas)
        sim_nao "Continuar com essas respostas?" S || return 0
        cabecalho_instalacao
        instalar_docker
        instalar
        exit 0
    fi
    banner
    titulo_caixa "O MATURADOR JÁ ESTÁ INSTALADO NESTA VPS"
    dica "https://${APP_HOST:-?}"
    echo ""
    sim_nao "Deseja atualizar para a versão mais nova?" S || exit 0
    banner
    titulo_caixa "ATUALIZANDO SEU SISTEMA" "$roxo"
    echo ""
    instalar_docker
    gerar_arquivo_deploy
    subir
    preparar_banco_evolution
    aguardar_sistema
    echo ""
    ok "${negrito}Atualização concluída!${reset}  ${cinza}https://$APP_HOST${reset}"
    exit 0
}

main() {
    verificacoes_iniciais

    if [ -f "$ENV_FILE" ]; then
        menu_instalacao_existente
    fi

    banner
    titulo_caixa "BEM-VINDO! VAMOS INSTALAR O MATURADOR"
    echo ""
    texto "É só ${negrito}uma pergunta${reset}: o seu domínio. Tenha em mãos o painel dele."
    echo ""
    info "Analisando a VPS..."
    COM_EVOLUTION=1
    detectar_ambiente
    descrever_ambiente
    sleep 2

    assistente
    cabecalho_instalacao
    instalar_docker
    instalar
}

main "$@"
