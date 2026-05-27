#!/bin/bash
# ============================================================
#  DETECTOR DE AMENAZAS - PROYECTO ACADÉMICO
#  Sistemas Operativos - Tema 8
#  Parte 3: Detección de amenazas y análisis de logs
# ============================================================

# ---------- Colores ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- Configuración ----------
LOG_FILE="/tmp/detector_log.txt"
MALWARE_LOG="/tmp/malware_activity.log"
INTERVAL=5              # Segundos entre cada ciclo de monitoreo
CPU_UMBRAL=80           # % de CPU que dispara alerta
RAM_UMBRAL=80           # % de RAM que dispara alerta
DISK_UMBRAL=85          # % de disco que dispara alerta
MAX_PROCS_POR_USUARIO=40  # Máximo procesos normales por usuario

> "$LOG_FILE"

# ---------- Función: Logging ----------
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ---------- Banner ----------
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     DETECTOR DE AMENAZAS EN TIEMPO REAL  ║"
echo "  ║     Sistemas Operativos — Parte 3        ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Umbrales de alerta:"
echo -e "  ${RED}CPU:${NC}   > ${CPU_UMBRAL}%"
echo -e "  ${YELLOW}RAM:${NC}   > ${RAM_UMBRAL}%"
echo -e "  ${CYAN}DISCO:${NC} > ${DISK_UMBRAL}%"
echo -e "  Intervalo de monitoreo: ${INTERVAL}s"
echo -e "  Log en: ${LOG_FILE}"
echo -e "\n  Presiona Ctrl+C para salir\n"
sleep 2

# ============================================================
#  FUNCIÓN: Monitorear CPU
# ============================================================
check_cpu() {
    # Obtener uso de CPU (idle = tiempo libre, cpu_use = uso real)
    local cpu_idle
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%us,')
    local cpu_use
    cpu_use=$(echo "100 - $cpu_idle" | bc 2>/dev/null || echo "N/A")

    echo -e "  ${BOLD}CPU:${NC} ${cpu_use}% en uso"

    # Alerta si supera el umbral
    if [ "$cpu_use" != "N/A" ]; then
        local int_cpu=${cpu_use%.*}
        if [ "$int_cpu" -ge "$CPU_UMBRAL" ] 2>/dev/null; then
            log "${RED}[ALERTA CPU] Uso crítico: ${cpu_use}% — Umbral: ${CPU_UMBRAL}%${NC}"
            echo -e "  ${RED}  ⚠ ALERTA: CPU al ${cpu_use}% — Posible proceso malicioso${NC}"

            # Mostrar top 5 procesos que más CPU consumen
            echo -e "  ${RED}  Top 5 procesos por CPU:${NC}"
            ps aux --sort=-%cpu | awk 'NR==1 || NR<=6 {printf "    %-10s %-8s %-8s %s\n", $1, $2, $3, $11}' | head -7
        fi
    fi
}

# ============================================================
#  FUNCIÓN: Monitorear RAM
# ============================================================
check_ram() {
    local total_mem
    total_mem=$(free | awk '/^Mem:/{print $2}')
    local used_mem
    used_mem=$(free | awk '/^Mem:/{print $3}')
    local pct_used
    pct_used=$(awk "BEGIN {printf \"%.1f\", ($used_mem/$total_mem)*100}")

    local total_h
    total_h=$(free -h | awk '/^Mem:/{print $2}')
    local used_h
    used_h=$(free -h | awk '/^Mem:/{print $3}')

    echo -e "  ${BOLD}RAM:${NC} ${used_h} / ${total_h} (${pct_used}%)"

    # Alerta si supera el umbral
    local int_pct=${pct_used%.*}
    if [ "$int_pct" -ge "$RAM_UMBRAL" ] 2>/dev/null; then
        log "${YELLOW}[ALERTA RAM] Uso crítico: ${pct_used}% — Umbral: ${RAM_UMBRAL}%${NC}"
        echo -e "  ${YELLOW}  ⚠ ALERTA: RAM al ${pct_used}% — Posible fuga de memoria${NC}"

        # Mostrar top 5 procesos por RAM
        echo -e "  ${YELLOW}  Top 5 procesos por RAM:${NC}"
        ps aux --sort=-%mem | awk 'NR==1 || NR<=6 {printf "    %-10s %-8s %-8s %s\n", $1, $2, $4, $11}' | head -7
    fi

    # Verificar archivos en /dev/shm (RAM filesystem)
    local shm_size
    shm_size=$(du -sh /dev/shm 2>/dev/null | cut -f1)
    echo -e "  ${BOLD}RAM FS (/dev/shm):${NC} $shm_size en uso"
    if [ -n "$(ls /dev/shm/malware* 2>/dev/null)" ]; then
        log "${YELLOW}[SOSPECHOSO] Archivos malware_* detectados en /dev/shm${NC}"
        echo -e "  ${YELLOW}  ⚠ Archivos sospechosos en RAM filesystem:${NC}"
        ls /dev/shm/malware* 2>/dev/null | while read -r f; do
            echo "    → $f"
        done
    fi
}

# ============================================================
#  FUNCIÓN: Monitorear Disco
# ============================================================
check_disk() {
    local disk_pct
    disk_pct=$(df / | awk 'NR==2{print $5}' | tr -d '%')
    local disk_info
    disk_info=$(df -h / | awk 'NR==2{print $3 " / " $2}')

    echo -e "  ${BOLD}DISCO (/):${NC} $disk_info (${disk_pct}%)"

    if [ "$disk_pct" -ge "$DISK_UMBRAL" ] 2>/dev/null; then
        log "${CYAN}[ALERTA DISCO] Uso crítico: ${disk_pct}% — Umbral: ${DISK_UMBRAL}%${NC}"
        echo -e "  ${CYAN}  ⚠ ALERTA: Disco al ${disk_pct}% — Posible saturación${NC}"
    fi

    # Detectar directorio del malware simulado
    if [ -d "/tmp/malware_disco_"* ] 2>/dev/null; then
        local mal_size
        mal_size=$(du -sh /tmp/malware_disco_* 2>/dev/null | cut -f1)
        log "${CYAN}[SOSPECHOSO] Directorio malware en /tmp detectado — Tamaño: $mal_size${NC}"
        echo -e "  ${CYAN}  ⚠ Directorio sospechoso en /tmp con ${mal_size} de datos${NC}"
    fi
}

# ============================================================
#  FUNCIÓN: Detectar procesos sospechosos
# ============================================================
check_processes() {
    echo -e "  ${BOLD}PROCESOS:${NC}"

    # Contar total de procesos
    local total_procs
    total_procs=$(ps aux | wc -l)
    echo -e "    Total de procesos activos: $total_procs"

    # Detectar procesos por usuario que excedan el máximo normal
    echo -e "    Procesos por usuario:"
    ps aux | awk 'NR>1{print $1}' | sort | uniq -c | sort -rn | while read -r count user; do
        if [ "$count" -ge "$MAX_PROCS_POR_USUARIO" ]; then
            log "${RED}[ALERTA PROCESOS] Usuario '$user' tiene $count procesos activos — Anormal${NC}"
            echo -e "    ${RED}  ⚠ $user: $count procesos (EXCESIVO)${NC}"
        else
            echo -e "    ${GREEN}  ✓ $user: $count procesos${NC}"
        fi
    done

    # Detectar bucles infinitos (procesos con 100% CPU por mucho tiempo)
    local high_cpu_procs
    high_cpu_procs=$(ps aux | awk '$3 > 90 {print $1, $2, $3, $11}')
    if [ -n "$high_cpu_procs" ]; then
        log "${RED}[ALERTA] Procesos con >90% CPU detectados:${NC}"
        echo -e "  ${RED}  ⚠ Procesos con >90% CPU:${NC}"
        echo "$high_cpu_procs" | while read -r line; do
            echo "    → $line"
            log "    → $line"
        done
    fi
}

# ============================================================
#  FUNCIÓN: Revisar puertos abiertos
# ============================================================
check_ports() {
    echo -e "  ${BOLD}PUERTOS ABIERTOS:${NC}"
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | awk 'NR>1{print "    Puerto:", $4, "| Proceso:", $7}' | head -10
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | awk 'NR>2{print "    Puerto:", $4, "| Proceso:", $7}' | head -10
    else
        echo "    (instala iproute2 o net-tools para ver puertos)"
    fi
}

# ============================================================
#  FUNCIÓN: Revisar archivos sospechosos en /tmp
# ============================================================
check_tmp() {
    echo -e "  ${BOLD}ARCHIVOS EN /tmp:${NC}"
    local tmp_count
    tmp_count=$(ls /tmp/ 2>/dev/null | wc -l)
    echo -e "    Total archivos en /tmp: $tmp_count"

    # Buscar archivos creados en los últimos 10 minutos
    local recent_files
    recent_files=$(find /tmp -maxdepth 2 -newer /tmp -name "*malware*" 2>/dev/null)
    if [ -n "$recent_files" ]; then
        log "${RED}[SOSPECHOSO] Archivos con nombre 'malware' encontrados en /tmp${NC}"
        echo -e "  ${RED}  ⚠ Archivos sospechosos detectados:${NC}"
        echo "$recent_files" | while read -r f; do
            echo "    → $f"
        done
    fi
}

# ============================================================
#  FUNCIÓN: Revisar log del malware simulado
# ============================================================
check_malware_log() {
    if [ -f "$MALWARE_LOG" ]; then
        local lines
        lines=$(wc -l < "$MALWARE_LOG")
        echo -e "  ${BOLD}LOG MALWARE:${NC} $lines líneas registradas"
        echo -e "  ${YELLOW}  Últimas 3 entradas:${NC}"
        tail -3 "$MALWARE_LOG" | while read -r line; do
            echo "    $line"
        done
    fi
}

# ============================================================
#  BUCLE PRINCIPAL DE MONITOREO
# ============================================================
while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   MONITOREO ACTIVO — $(date '+%H:%M:%S')          ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${BOLD}▶ MÉTRICAS DEL SISTEMA${NC}"
    check_cpu
    echo ""
    check_ram
    echo ""
    check_disk
    echo ""

    echo -e "${BOLD}▶ ANÁLISIS DE PROCESOS${NC}"
    check_processes
    echo ""

    echo -e "${BOLD}▶ RED Y PUERTOS${NC}"
    check_ports
    echo ""

    echo -e "${BOLD}▶ ARCHIVOS SOSPECHOSOS${NC}"
    check_tmp
    echo ""

    echo -e "${BOLD}▶ ACTIVIDAD DEL MALWARE${NC}"
    check_malware_log
    echo ""

    echo -e "${GREEN}  [✓] Log guardado en: $LOG_FILE${NC}"
    echo -e "  Próximo ciclo en ${INTERVAL}s... (Ctrl+C para salir)\n"

    sleep "$INTERVAL"
done
