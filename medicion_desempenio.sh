#!/bin/bash
# ============================================================
#  MEDICIÓN DE DESEMPEÑO — PROYECTO ACADÉMICO
#  Sistemas Operativos - Tema 8
#  Parte 5: Métricas de rendimiento del sistema
# ------------------------------------------------------------
#  Mide y compara 3 escenarios:
#    Escenario A → Sistema Limpio    (baseline)
#    Escenario B → Sistema Infectado (con malware activo)
#    Escenario C → Sistema Protegido (después de contención)
#
#  Herramientas usadas: top, free, iostat, ping, df, ps
#  Genera: reporte TXT + CSV para análisis
# ============================================================

# ---------- Colores ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- Configuración ----------
RESULTS_DIR="/tmp/metricas_so"
REPORTE_TXT="${RESULTS_DIR}/reporte_desempenio.txt"
REPORTE_CSV="${RESULTS_DIR}/metricas.csv"
MUESTRAS=5          # Número de muestras por métrica
INTERVALO=3         # Segundos entre muestras
HOST_PING="8.8.8.8" # Host para medir latencia de red (dentro de red virtual)
FECHA=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$RESULTS_DIR"

# ============================================================
#  FUNCIONES DE UTILIDAD
# ============================================================

log_reporte() {
    echo -e "$1" | tee -a "$REPORTE_TXT"
}

separador() {
    log_reporte "\n$(printf '─%.0s' {1..60})"
}

titulo() {
    separador
    log_reporte "  $1"
    separador
}

# ============================================================
#  FUNCIONES DE MEDICIÓN (cada una retorna valor numérico)
# ============================================================

# --- CPU: Promedio de uso en N muestras ---
medir_cpu() {
    local suma=0
    local muestra
    for i in $(seq 1 "$MUESTRAS"); do
        muestra=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | tr -d '%')
        muestra=${muestra:-0}
        suma=$(awk "BEGIN {print $suma + $muestra}")
        sleep "$INTERVALO"
    done
    awk "BEGIN {printf \"%.2f\", $suma / $MUESTRAS}"
}

# --- RAM: Porcentaje de uso actual ---
medir_ram_pct() {
    local total used
    total=$(free | awk '/^Mem:/{print $2}')
    used=$(free  | awk '/^Mem:/{print $3}')
    awk "BEGIN {printf \"%.2f\", ($used/$total)*100}"
}

# --- RAM: MB usados ---
medir_ram_mb() {
    free -m | awk '/^Mem:/{print $3}'
}

# --- RAM: MB disponibles ---
medir_ram_libre_mb() {
    free -m | awk '/^Mem:/{print $7}'
}

# --- Disco: Porcentaje de uso en / ---
medir_disco_pct() {
    df / | awk 'NR==2{print $5}' | tr -d '%'
}

# --- Disco: Espacio usado en MB ---
medir_disco_mb() {
    df -m / | awk 'NR==2{print $3}'
}

# --- Disco: Velocidad de escritura (MB/s) ---
medir_disco_escritura() {
    local tmp_test="${RESULTS_DIR}/test_escritura_$$"
    local result
    result=$(dd if=/dev/zero of="$tmp_test" bs=1M count=50 conv=fdatasync 2>&1 \
             | grep -oP '[0-9.]+ MB/s' | awk '{print $1}')
    rm -f "$tmp_test"
    echo "${result:-0}"
}

# --- Disco: Velocidad de lectura (MB/s) ---
medir_disco_lectura() {
    local tmp_test="${RESULTS_DIR}/test_lectura_$$"
    dd if=/dev/zero of="$tmp_test" bs=1M count=50 conv=fdatasync 2>/dev/null
    local result
    result=$(dd if="$tmp_test" of=/dev/null bs=1M 2>&1 \
             | grep -oP '[0-9.]+ MB/s' | awk '{print $1}')
    rm -f "$tmp_test"
    echo "${result:-0}"
}

# --- Red: Latencia promedio (ms) ---
medir_latencia() {
    local result
    result=$(ping -c 4 -W 2 "$HOST_PING" 2>/dev/null \
             | tail -1 | awk -F '/' '{print $5}')
    echo "${result:-999}"
}

# --- Procesos: Total de procesos activos ---
medir_procesos() {
    ps aux | wc -l
}

# --- Procesos: Total de procesos del usuario actual ---
medir_procesos_usuario() {
    ps aux | awk -v u="$(whoami)" '$1==u' | wc -l
}

# --- Tiempo de respuesta del sistema (ms) ---
medir_tiempo_respuesta() {
    local inicio fin elapsed
    inicio=$(date +%s%N)
    # Operación de referencia: listar 1000 archivos
    ls -la /proc/ > /dev/null 2>&1
    fin=$(date +%s%N)
    elapsed=$(( (fin - inicio) / 1000000 ))
    echo "$elapsed"
}

# --- Load Average (carga del sistema 1 minuto) ---
medir_load_avg() {
    uptime | awk -F 'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' '
}

# ============================================================
#  FUNCIÓN PRINCIPAL: Capturar todas las métricas de un escenario
# ============================================================
capturar_escenario() {
    local nombre="$1"      # Nombre del escenario
    local etiqueta="$2"    # Etiqueta corta (limpio/infectado/protegido)

    echo -e "\n${CYAN}${BOLD}[*] Midiendo: $nombre${NC}"
    echo -e "    Tomando ${MUESTRAS} muestras con ${INTERVALO}s de intervalo...\n"

    # --- Medir cada métrica ---
    echo -ne "    CPU...              "
    local cpu
    cpu=$(medir_cpu)
    echo -e "${GREEN}${cpu}%${NC}"

    echo -ne "    RAM (%)...          "
    local ram_pct
    ram_pct=$(medir_ram_pct)
    echo -e "${GREEN}${ram_pct}%${NC}"

    echo -ne "    RAM usada (MB)...   "
    local ram_mb
    ram_mb=$(medir_ram_mb)
    echo -e "${GREEN}${ram_mb} MB${NC}"

    echo -ne "    RAM libre (MB)...   "
    local ram_libre
    ram_libre=$(medir_ram_libre_mb)
    echo -e "${GREEN}${ram_libre} MB${NC}"

    echo -ne "    Disco (%)...        "
    local disco_pct
    disco_pct=$(medir_disco_pct)
    echo -e "${GREEN}${disco_pct}%${NC}"

    echo -ne "    Disco usado (MB)... "
    local disco_mb
    disco_mb=$(medir_disco_mb)
    echo -e "${GREEN}${disco_mb} MB${NC}"

    echo -ne "    Escritura disco...  "
    local disco_write
    disco_write=$(medir_disco_escritura)
    echo -e "${GREEN}${disco_write} MB/s${NC}"

    echo -ne "    Lectura disco...    "
    local disco_read
    disco_read=$(medir_disco_lectura)
    echo -e "${GREEN}${disco_read} MB/s${NC}"

    echo -ne "    Latencia red...     "
    local latencia
    latencia=$(medir_latencia)
    echo -e "${GREEN}${latencia} ms${NC}"

    echo -ne "    Total procesos...   "
    local procs
    procs=$(medir_procesos)
    echo -e "${GREEN}${procs}${NC}"

    echo -ne "    Procs. usuario...   "
    local procs_usr
    procs_usr=$(medir_procesos_usuario)
    echo -e "${GREEN}${procs_usr}${NC}"

    echo -ne "    Tiempo respuesta... "
    local t_resp
    t_resp=$(medir_tiempo_respuesta)
    echo -e "${GREEN}${t_resp} ms${NC}"

    echo -ne "    Load Average...     "
    local load
    load=$(medir_load_avg)
    echo -e "${GREEN}${load}${NC}"

    # --- Guardar en CSV ---
    echo "${etiqueta},${cpu},${ram_pct},${ram_mb},${ram_libre},${disco_pct},${disco_mb},${disco_write},${disco_read},${latencia},${procs},${procs_usr},${t_resp},${load}" \
        >> "$REPORTE_CSV"

    # --- Guardar en variables globales para el reporte ---
    # Usamos un archivo temporal por escenario
    cat > "${RESULTS_DIR}/esc_${etiqueta}.dat" <<EOF
cpu=$cpu
ram_pct=$ram_pct
ram_mb=$ram_mb
ram_libre=$ram_libre
disco_pct=$disco_pct
disco_mb=$disco_mb
disco_write=$disco_write
disco_read=$disco_read
latencia=$latencia
procs=$procs
procs_usr=$procs_usr
t_resp=$t_resp
load=$load
EOF

    echo -e "\n    ${GREEN}[✓] Métricas de '$nombre' guardadas${NC}"
}

# ============================================================
#  FUNCIÓN: Calcular degradación entre dos escenarios
# ============================================================
calcular_delta() {
    local val_base="$1"
    local val_comp="$2"
    local unidad="$3"
    local mas_es_malo="$4"  # "si" = más alto es peor, "no" = más alto es mejor

    local delta
    delta=$(awk "BEGIN {
        if ($val_base != 0)
            printf \"%.1f\", (($val_comp - $val_base) / $val_base) * 100
        else
            print \"N/A\"
    }")

    local simbolo=""
    if [ "$mas_es_malo" = "si" ]; then
        # Mayor valor = peor rendimiento
        if awk "BEGIN {exit !($delta > 10)}" 2>/dev/null; then
            simbolo="${RED}▲ +${delta}%${NC}"
        elif awk "BEGIN {exit !($delta < -10)}" 2>/dev/null; then
            simbolo="${GREEN}▼ ${delta}%${NC}"
        else
            simbolo="${NC}≈ ${delta}%${NC}"
        fi
    else
        # Mayor valor = mejor rendimiento
        if awk "BEGIN {exit !($delta < -10)}" 2>/dev/null; then
            simbolo="${RED}▼ ${delta}%${NC}"
        elif awk "BEGIN {exit !($delta > 10)}" 2>/dev/null; then
            simbolo="${GREEN}▲ +${delta}%${NC}"
        else
            simbolo="${NC}≈ ${delta}%${NC}"
        fi
    fi

    echo -e "${val_comp}${unidad}  (${simbolo})"
}

# ============================================================
#  FUNCIÓN: Generar reporte final comparativo
# ============================================================
generar_reporte() {
    # Cargar datos de cada escenario
    source "${RESULTS_DIR}/esc_limpio.dat"
    local cpu_L=$cpu ram_pct_L=$ram_pct ram_mb_L=$ram_mb ram_libre_L=$ram_libre
    local disco_pct_L=$disco_pct disco_mb_L=$disco_mb disco_write_L=$disco_write
    local disco_read_L=$disco_read latencia_L=$latencia procs_L=$procs
    local procs_usr_L=$procs_usr t_resp_L=$t_resp load_L=$load

    source "${RESULTS_DIR}/esc_infectado.dat"
    local cpu_I=$cpu ram_pct_I=$ram_pct ram_mb_I=$ram_mb ram_libre_I=$ram_libre
    local disco_pct_I=$disco_pct disco_mb_I=$disco_mb disco_write_I=$disco_write
    local disco_read_I=$disco_read latencia_I=$latencia procs_I=$procs
    local procs_usr_I=$procs_usr t_resp_I=$t_resp load_I=$load

    source "${RESULTS_DIR}/esc_protegido.dat"
    local cpu_P=$cpu ram_pct_P=$ram_pct ram_mb_P=$ram_mb ram_libre_P=$ram_libre
    local disco_pct_P=$disco_pct disco_mb_P=$disco_mb disco_write_P=$disco_write
    local disco_read_P=$disco_read latencia_P=$latencia procs_P=$procs
    local procs_usr_P=$procs_usr t_resp_P=$t_resp load_P=$load

    # Escribir reporte
    > "$REPORTE_TXT"

    log_reporte "============================================================"
    log_reporte "   REPORTE DE MEDICIÓN DE DESEMPEÑO"
    log_reporte "   Sistemas Operativos — Tema 8: Seguridad y Desempeño"
    log_reporte "   Fecha: $FECHA"
    log_reporte "   Muestras por escenario: $MUESTRAS | Intervalo: ${INTERVALO}s"
    log_reporte "============================================================"

    log_reporte "\n  Sistema: $(uname -n)"
    log_reporte "  OS:      $(uname -o) $(uname -r)"
    log_reporte "  CPU:     $(nproc) núcleo(s) — $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    log_reporte "  RAM:     $(free -h | awk '/^Mem:/{print $2}') total"
    log_reporte "  Disco:   $(df -h / | awk 'NR==2{print $2}') total en /"

    titulo "TABLA COMPARATIVA DE MÉTRICAS"

    printf "\n%-28s %-16s %-16s %-16s\n" \
        "MÉTRICA" "LIMPIO (A)" "INFECTADO (B)" "PROTEGIDO (C)" \
        >> "$REPORTE_TXT"
    printf "%-28s %-16s %-16s %-16s\n" \
        "$(printf '─%.0s' {1..27})" "$(printf '─%.0s' {1..15})" \
        "$(printf '─%.0s' {1..15})" "$(printf '─%.0s' {1..15})" \
        >> "$REPORTE_TXT"

    # Función para fila de tabla
    fila_tabla() {
        printf "%-28s %-16s %-16s %-16s\n" "$1" "$2" "$3" "$4" >> "$REPORTE_TXT"
    }

    fila_tabla "Uso CPU (%)"           "${cpu_L}%"          "${cpu_I}%"          "${cpu_P}%"
    fila_tabla "Uso RAM (%)"           "${ram_pct_L}%"      "${ram_pct_I}%"      "${ram_pct_P}%"
    fila_tabla "RAM usada (MB)"        "${ram_mb_L} MB"     "${ram_mb_I} MB"     "${ram_mb_P} MB"
    fila_tabla "RAM disponible (MB)"   "${ram_libre_L} MB"  "${ram_libre_I} MB"  "${ram_libre_P} MB"
    fila_tabla "Disco usado (%)"       "${disco_pct_L}%"    "${disco_pct_I}%"    "${disco_pct_P}%"
    fila_tabla "Disco usado (MB)"      "${disco_mb_L} MB"   "${disco_mb_I} MB"   "${disco_mb_P} MB"
    fila_tabla "Escritura disco(MB/s)" "${disco_write_L}"   "${disco_write_I}"   "${disco_write_P}"
    fila_tabla "Lectura disco (MB/s)"  "${disco_read_L}"    "${disco_read_I}"    "${disco_read_P}"
    fila_tabla "Latencia red (ms)"     "${latencia_L} ms"   "${latencia_I} ms"   "${latencia_P} ms"
    fila_tabla "Total procesos"        "${procs_L}"         "${procs_I}"         "${procs_P}"
    fila_tabla "Procs. usuario"        "${procs_usr_L}"     "${procs_usr_I}"     "${procs_usr_P}"
    fila_tabla "T. respuesta (ms)"     "${t_resp_L} ms"     "${t_resp_I} ms"     "${t_resp_P} ms"
    fila_tabla "Load Average"          "${load_L}"          "${load_I}"          "${load_P}"

    titulo "ANÁLISIS DE DEGRADACIÓN (Limpio → Infectado)"

    log_reporte "  Una variación > 10% se considera significativa.\n"
    log_reporte "  ▲ = Aumento (malo para CPU/RAM/Disco/Latencia)"
    log_reporte "  ▼ = Disminución (malo para velocidades de disco)\n"

    echo -ne "  CPU:              " >> "$REPORTE_TXT"
    calcular_delta "$cpu_L"          "$cpu_I"          "%"    "si"  >> "$REPORTE_TXT"
    echo -ne "  RAM (%):          " >> "$REPORTE_TXT"
    calcular_delta "$ram_pct_L"      "$ram_pct_I"      "%"    "si"  >> "$REPORTE_TXT"
    echo -ne "  RAM usada:        " >> "$REPORTE_TXT"
    calcular_delta "$ram_mb_L"       "$ram_mb_I"       " MB"  "si"  >> "$REPORTE_TXT"
    echo -ne "  Latencia:         " >> "$REPORTE_TXT"
    calcular_delta "$latencia_L"     "$latencia_I"     " ms"  "si"  >> "$REPORTE_TXT"
    echo -ne "  Procesos activos: " >> "$REPORTE_TXT"
    calcular_delta "$procs_L"        "$procs_I"        ""     "si"  >> "$REPORTE_TXT"
    echo -ne "  T. respuesta:     " >> "$REPORTE_TXT"
    calcular_delta "$t_resp_L"       "$t_resp_I"       " ms"  "si"  >> "$REPORTE_TXT"
    echo -ne "  Escrit. disco:    " >> "$REPORTE_TXT"
    calcular_delta "$disco_write_L"  "$disco_write_I"  " MB/s" "no" >> "$REPORTE_TXT"

    titulo "ANÁLISIS DE RECUPERACIÓN (Infectado → Protegido)"

    log_reporte "  Mide qué tanto se recupera el sistema tras la contención.\n"

    echo -ne "  CPU:              " >> "$REPORTE_TXT"
    calcular_delta "$cpu_I"          "$cpu_P"          "%"    "si"  >> "$REPORTE_TXT"
    echo -ne "  RAM (%):          " >> "$REPORTE_TXT"
    calcular_delta "$ram_pct_I"      "$ram_pct_P"      "%"    "si"  >> "$REPORTE_TXT"
    echo -ne "  RAM usada:        " >> "$REPORTE_TXT"
    calcular_delta "$ram_mb_I"       "$ram_mb_P"       " MB"  "si"  >> "$REPORTE_TXT"
    echo -ne "  Latencia:         " >> "$REPORTE_TXT"
    calcular_delta "$latencia_I"     "$latencia_P"     " ms"  "si"  >> "$REPORTE_TXT"
    echo -ne "  Procesos activos: " >> "$REPORTE_TXT"
    calcular_delta "$procs_I"        "$procs_P"        ""     "si"  >> "$REPORTE_TXT"
    echo -ne "  T. respuesta:     " >> "$REPORTE_TXT"
    calcular_delta "$t_resp_I"       "$t_resp_P"       " ms"  "si"  >> "$REPORTE_TXT"
    echo -ne "  Escrit. disco:    " >> "$REPORTE_TXT"
    calcular_delta "$disco_write_I"  "$disco_write_P"  " MB/s" "no" >> "$REPORTE_TXT"

    titulo "MODELADO ANALÍTICO"

    log_reporte "  Parte 6 del proyecto: indicadores calculados"

    # Índice de degradación (0 a 100, cuánto se degradó el sistema)
    local idx_deg
    idx_deg=$(awk "BEGIN {
        cpu_d   = ($cpu_I   - $cpu_L)   / 100 * 0.35
        ram_d   = ($ram_pct_I - $ram_pct_L) / 100 * 0.30
        t_d     = ($t_resp_I - $t_resp_L) / ($t_resp_L > 0 ? $t_resp_L : 1) * 0.20
        proc_d  = ($procs_I - $procs_L) / ($procs_L > 0 ? $procs_L : 1) * 0.15
        total   = (cpu_d + ram_d + t_d + proc_d) * 100
        if (total > 100) total = 100
        if (total < 0)   total = 0
        printf \"%.1f\", total
    }")

    # Índice de recuperación (qué tan bien volvió el sistema)
    local idx_rec
    idx_rec=$(awk "BEGIN {
        cpu_r  = ($cpu_I   > 0) ? ($cpu_I   - $cpu_P)   / $cpu_I   : 0
        ram_r  = ($ram_pct_I > 0) ? ($ram_pct_I - $ram_pct_P) / $ram_pct_I : 0
        t_r    = ($t_resp_I > 0) ? ($t_resp_I - $t_resp_P) / $t_resp_I : 0
        total  = (cpu_r + ram_r + t_r) / 3 * 100
        if (total > 100) total = 100
        if (total < 0)   total = 0
        printf \"%.1f\", total
    }")

    # Saturación de CPU
    local sat_cpu
    sat_cpu=$(awk "BEGIN {printf \"%.1f\", $cpu_I - $cpu_L}")

    # Incremento de latencia
    local inc_lat
    inc_lat=$(awk "BEGIN {printf \"%.1f\", $latencia_I - $latencia_L}")

    # Throughput de disco (promedio entre escenarios)
    local throughput_l throughput_i throughput_p
    throughput_l=$(awk "BEGIN {printf \"%.1f\", ($disco_write_L + $disco_read_L) / 2}")
    throughput_i=$(awk "BEGIN {printf \"%.1f\", ($disco_write_I + $disco_read_I) / 2}")
    throughput_p=$(awk "BEGIN {printf \"%.1f\", ($disco_write_P + $disco_read_P) / 2}")

    log_reporte "\n  Indicador                    Valor"
    log_reporte "  $(printf '─%.0s' {1..45})"
    log_reporte "  Índice de Degradación        ${idx_deg}/100  (0=sin cambio, 100=colapso)"
    log_reporte "  Índice de Recuperación       ${idx_rec}%     (100%=recuperación total)"
    log_reporte "  Saturación de CPU            +${sat_cpu}pp  (puntos porcentuales)"
    log_reporte "  Incremento de Latencia       +${inc_lat} ms"
    log_reporte "  Throughput Disco — Limpio    ${throughput_l} MB/s"
    log_reporte "  Throughput Disco — Infectado ${throughput_i} MB/s"
    log_reporte "  Throughput Disco — Protegido ${throughput_p} MB/s"
    log_reporte "  Procesos generados (malware) $((procs_I - procs_L)) procesos adicionales"

    titulo "CONCLUSIONES AUTOMÁTICAS"

    # CPU
    local cpu_deg
    cpu_deg=$(awk "BEGIN {print ($cpu_I - $cpu_L)}")
    if awk "BEGIN {exit !($cpu_deg > 50)}" 2>/dev/null; then
        log_reporte "  [CPU]   Degradación SEVERA (+${cpu_deg}pp). El malware saturó el procesador."
    elif awk "BEGIN {exit !($cpu_deg > 20)}" 2>/dev/null; then
        log_reporte "  [CPU]   Degradación MODERADA (+${cpu_deg}pp). Impacto notable en rendimiento."
    else
        log_reporte "  [CPU]   Degradación LEVE (+${cpu_deg}pp)."
    fi

    # RAM
    local ram_deg
    ram_deg=$(awk "BEGIN {print ($ram_pct_I - $ram_pct_L)}")
    if awk "BEGIN {exit !($ram_deg > 40)}" 2>/dev/null; then
        log_reporte "  [RAM]   Consumo CRÍTICO de memoria (+${ram_deg}pp)."
    else
        log_reporte "  [RAM]   Consumo MODERADO de RAM (+${ram_deg}pp)."
    fi

    # Recuperación
    if awk "BEGIN {exit !($idx_rec > 70)}" 2>/dev/null; then
        log_reporte "  [PROT]  Recuperación EXITOSA (${idx_rec}%). Las medidas de contención fueron efectivas."
    elif awk "BEGIN {exit !($idx_rec > 40)}" 2>/dev/null; then
        log_reporte "  [PROT]  Recuperación PARCIAL (${idx_rec}%). Se requieren medidas adicionales."
    else
        log_reporte "  [PROT]  Recuperación INSUFICIENTE (${idx_rec}%). Revisar medidas de contención."
    fi

    log_reporte "\n  Índice de Degradación Global: ${idx_deg}/100"
    log_reporte "  Índice de Recuperación:       ${idx_rec}%"

    separador
    log_reporte "\n  Archivos generados:"
    log_reporte "    Reporte texto: $REPORTE_TXT"
    log_reporte "    Datos CSV:     $REPORTE_CSV"
    log_reporte "    Datos crudos:  ${RESULTS_DIR}/esc_*.dat"
    separador
    log_reporte "\n  Fin del reporte — $(date '+%Y-%m-%d %H:%M:%S')"
    log_reporte ""
}

# ============================================================
#  ENCABEZADO CSV
# ============================================================
echo "escenario,cpu_pct,ram_pct,ram_mb,ram_libre_mb,disco_pct,disco_mb,disco_write_mbs,disco_read_mbs,latencia_ms,procs_total,procs_usuario,t_respuesta_ms,load_avg" \
    > "$REPORTE_CSV"

# ============================================================
#  BANNER Y MENÚ PRINCIPAL
# ============================================================
clear
echo -e "${BLUE}${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║         MEDICIÓN DE DESEMPEÑO — SISTEMAS OPERATIVOS     ║"
echo "  ║         Parte 5: Métricas de rendimiento del sistema    ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}Escenarios disponibles:${NC}"
echo -e "  ${GREEN}[A]${NC} Sistema Limpio    → Medir baseline antes del malware"
echo -e "  ${RED}[B]${NC} Sistema Infectado → Medir con malware_sim.sh corriendo"
echo -e "  ${CYAN}[C]${NC} Sistema Protegido → Medir después de kill_malware.sh"
echo -e "  ${YELLOW}[T]${NC} Guiado completo  → Te guía paso a paso por A→B→C"
echo -e "  ${BOLD}[R]${NC} Generar reporte  → Solo si ya tienes datos de A, B y C"
echo ""
read -rp "  Opción: " OPCION

case "$OPCION" in
    [Aa])
        echo -e "\n${GREEN}[*] Midiendo Escenario A: Sistema Limpio${NC}"
        echo -e "    Asegúrate de que malware_sim.sh NO esté corriendo.\n"
        read -rp "    ¿Listo? (Enter para continuar)"
        capturar_escenario "Sistema Limpio" "limpio"
        echo -e "\n${GREEN}[✓] Escenario A completado. Ahora ejecuta malware_sim.sh y luego mide el Escenario B.${NC}\n"
        ;;
    [Bb])
        if [ ! -f "${RESULTS_DIR}/esc_limpio.dat" ]; then
            echo -e "\n${RED}[!] Mide primero el Escenario A (Sistema Limpio).${NC}\n"
            exit 1
        fi
        echo -e "\n${RED}[*] Midiendo Escenario B: Sistema Infectado${NC}"
        echo -e "    Asegúrate de que malware_sim.sh SÍ esté corriendo en otra terminal.\n"
        read -rp "    ¿El malware está activo? (Enter para continuar)"
        capturar_escenario "Sistema Infectado" "infectado"
        echo -e "\n${YELLOW}[✓] Escenario B completado. Ejecuta kill_malware.sh y luego mide el Escenario C.${NC}\n"
        ;;
    [Cc])
        if [ ! -f "${RESULTS_DIR}/esc_infectado.dat" ]; then
            echo -e "\n${RED}[!] Mide primero el Escenario B (Sistema Infectado).${NC}\n"
            exit 1
        fi
        echo -e "\n${CYAN}[*] Midiendo Escenario C: Sistema Protegido${NC}"
        echo -e "    Asegúrate de haber ejecutado kill_malware.sh.\n"
        read -rp "    ¿El malware fue detenido? (Enter para continuar)"
        capturar_escenario "Sistema Protegido" "protegido"
        generar_reporte
        echo -e "\n${GREEN}[✓] Reporte generado en: $REPORTE_TXT${NC}"
        echo -e "${GREEN}[✓] CSV generado en:     $REPORTE_CSV${NC}\n"
        ;;
    [Tt])
        # Modo guiado completo
        echo -e "\n${BLUE}${BOLD}[MODO GUIADO] Se medirán los 3 escenarios paso a paso.${NC}\n"

        echo -e "${GREEN}━━━ PASO 1/3: SISTEMA LIMPIO ━━━${NC}"
        echo -e "  Asegúrate de que malware_sim.sh NO esté corriendo."
        read -rp "  Presiona Enter cuando estés listo..."
        capturar_escenario "Sistema Limpio" "limpio"

        echo -e "\n${RED}━━━ PASO 2/3: SISTEMA INFECTADO ━━━${NC}"
        echo -e "  Abre otra terminal y ejecuta: ${BOLD}sudo ./malware_sim.sh${NC} (opción 5)"
        echo -e "  Espera unos segundos a que el malware comience a consumir recursos."
        read -rp "  Presiona Enter cuando el malware esté activo..."
        capturar_escenario "Sistema Infectado" "infectado"

        echo -e "\n${CYAN}━━━ PASO 3/3: SISTEMA PROTEGIDO ━━━${NC}"
        echo -e "  Ejecuta en otra terminal: ${BOLD}sudo ./kill_malware.sh${NC}"
        echo -e "  Espera a que termine la limpieza."
        read -rp "  Presiona Enter cuando el sistema esté limpio..."
        capturar_escenario "Sistema Protegido" "protegido"

        echo -e "\n${BLUE}[*] Generando reporte comparativo...${NC}"
        generar_reporte

        echo -e "\n${GREEN}${BOLD}[✓] ¡Medición completa!${NC}"
        echo -e "${GREEN}    Reporte: $REPORTE_TXT${NC}"
        echo -e "${GREEN}    CSV:     $REPORTE_CSV${NC}\n"
        ;;
    [Rr])
        if [ ! -f "${RESULTS_DIR}/esc_limpio.dat" ] || \
           [ ! -f "${RESULTS_DIR}/esc_infectado.dat" ] || \
           [ ! -f "${RESULTS_DIR}/esc_protegido.dat" ]; then
            echo -e "\n${RED}[!] Faltan datos. Mide los 3 escenarios antes de generar el reporte.${NC}\n"
            exit 1
        fi
        echo -e "\n${BLUE}[*] Generando reporte con datos existentes...${NC}"
        generar_reporte
        echo -e "\n${GREEN}[✓] Reporte generado en: $REPORTE_TXT${NC}\n"
        ;;
    *)
        echo -e "\n${RED}Opción inválida.${NC}\n"
        exit 1
        ;;
esac

# Mostrar reporte al final si existe
if [ -f "$REPORTE_TXT" ]; then
    echo ""
    read -rp "¿Mostrar reporte en pantalla? (s/n): " SHOW
    if [[ "$SHOW" =~ ^[Ss]$ ]]; then
        echo ""
        cat "$REPORTE_TXT"
    fi
fi
