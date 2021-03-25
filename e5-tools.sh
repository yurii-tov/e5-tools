[ "$OSTYPE" = "linux-gnu" ] || {
    IS_WINDOWS=true
}


export E5_ROOT_DIR_WINDOWS='c:/Program Files (x86)/1C Education/1CE5'
export E5_ROOT_DIR_LINUX='/opt/1CE5'
export E5_DBUTILS_WINDOWS="$E5_ROOT_DIR_WINDOWS/1CEduWeb/utils/1CE5DbUtils"


[ "$E5_BRANCH" = "oko" ] && {
    export E5_ROOT_DIR_WINDOWS='c:/Program Files (x86)/1C OKO'
    export E5_ROOT_DIR_LINUX='/opt/1COKO'
    export E5_DBUTILS_WINDOWS="$E5_ROOT_DIR_WINDOWS/1CEduWeb/utils/1COKODbUtils"
}


export E5_ROOT_DIR="$E5_ROOT_DIR_LINUX"


[ "$IS_WINDOWS" ] && {
    E5_ROOT_DIR="$E5_ROOT_DIR_WINDOWS"
}


export E5_CD_ROOT_DIR="{ cd '$E5_ROOT_DIR_LINUX' || cd '$E5_ROOT_DIR_WINDOWS'; } 2>/dev/null"


# server control


alias e5-server-status="ps -eH | sed -n '/StartServer/,/ java/ p'"
alias e5-server-stop="$E5_ROOT_DIR_LINUX/StopServer.sh"
alias e5-server-start="$E5_ROOT_DIR_LINUX/StartServer.sh &"
alias e5-server-restart='e5-server-stop; sleep 10; e5-server-start'


[ "$IS_WINDOWS" ] && {
    alias posh='c:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass'
    alias e5-server-status='posh "Get-Service *1c*"'
    alias e5-server-stop='posh "Get-Service *1c* | Stop-Service -Verbose" ; e5-server-status'
    alias e5-server-start='posh "Get-Service *1c* | Start-Service -Verbose" ; e5-server-status'
    alias e5-server-restart='e5-server-stop; sleep 10; e5-server-start'
}


# dbutils


function dbutils() {
    "$E5_ROOT_DIR/DBUtils.sh" "$@"
}


if [ "$IS_WINDOWS" ]; then
    function dbutils() {
        local -
        set -o pipefail
        "$E5_DBUTILS_WINDOWS" "$@" |& iconv -f cp866 -t utf-8
    }
fi


# e5-specific SQL client


function e5-isql() {
    local OPTIND=1
    while getopts "hc:r:i" o; do
        case $o in
            c) local sql="$OPTARG";;
            r) local ssh_spec=$OPTARG;;
            i) local in_place=true;;
            h)
                echo 'Executing sql commands/starting REPLs on local or remote e5 databases'
                echo '---------------------------------------------------------------------'
                echo 'Usage: e5-isql [-c <one-off sql command>]'
                echo '               [-r <remote hosts spec>] # e.g. user@host'
                echo '               [-i] # Edit db in-place'
                echo '               [-h] # Show help and exit'
                echo '               <path-to-db> # Relative to 1CEduWeb/data'
                echo 'Examples: e5-isql -c "select * from ruser;" -r myserver edu_main/ls.fdb'
                echo '          e5-isql -r myserver edu_main/ls.fdb'
                echo '          e5-isql -ir myserver -c "update rversion set version = 42;" edu_main/ls.fdb'
                echo '          e5-isql -i ls.fdb'
                return 0
                ;;
            ?) isql-e5 -h ; return 1 ;;
        esac
    done
    shift $(($OPTIND - 1))
    [ "$1" ] || { isql-e5 -h ; return 0; }
    local db_original="$1"
    local db_copy="$1"
    local cd_data_dir="$E5_CD_ROOT_DIR ; cd 1CEduWeb/data"
    local fetch_command="$cd_data_dir"" ; cat '$db_original'"

    # Fetch db
    [ "$ssh_spec" ] && fetch_command="ssh $ssh_spec \"$fetch_command\""
    [ "$ssh_spec" ] || [ -z "$in_place" ] && {
        local db_tmp=$(mktemp)
        bash -c "$fetch_command" > $db_tmp
        db_copy=$db_tmp
    }

    # Exec sql / start REPL
    local isql=isql
    [ "$OSTYPE" = "linux-gnu" ] && isql=isql-fb
    local isql_command="$isql -user sysdba -password masterkey $db_copy"
    [ "$sql" ] && {
        local sql_script=$(mktemp)
        echo "$sql" > $sql_script
        isql_command="$isql_command -i $sql_script"
    }
    bash -c "$isql_command"

    # Push db to remote host (if necessary)
    [ "$in_place" ] && [ "$ssh_spec" ] && {
        ssh $ssh_spec "$cd_data_dir"" ; cat > '$db_original'" < $db_copy
    }

    # # Clean up
    [ "$sql_script" ] && rm $sql_script
    [ "$db_tmp" ] && rm $db_tmp
}


# Messing with logs/postmortems


function e5-dump() {
    local OPTIND=1
    while getopts "hd:r:b:" o; do
        case $o in
            d) local dump_file="$(readlink -f "$OPTARG/logs_$(date '+%F_%H%M%S').tar.gz")";;
            r) local ssh_spec=$OPTARG;;
            b) local bases=$OPTARG;;
            h)
                echo 'Dumping various postmortem data: logs, config files, databases...'
                echo 'By default, write tar.gz stream into stdout'
                echo '-----------------------------------------------------------------'
                echo 'Usage: e5-dump [-d <directory where place logs .tar.gz>]'
                echo '               # By default, dumping tar stream into stdout'
                echo '               [-r <remote hosts spec, e.g. user@host>]'
                echo '               [-b <comma-separated list of bases to include into dump>]'
                echo '               # relative to 1CEduWeb/data directory'
                echo '               # e.g. -b edu_main/ls.fdb,x/ls.fdb'
                return 0 ;;
            ?) dump-e5-logs -h ; return 1 ;;
        esac
    done
    local command="$E5_CD_ROOT_DIR ; tar -cz 1CEduWeb/webapps/1CEduWeb/WEB-INF/{ls.xml,web.xml,log} 1CEduWeb/app*/build.properties common/jetty/etc/{*.properties,*.xml} common/jetty/logs"
    [ "$ssh_spec" ] && command="ssh $ssh_spec \"$command\""
    [ "$bases" ] && command="$command"" 1CEduWeb/data/${bases//,/ 1CEduWeb\/data\/}"
    [ "$dump_file" ] && {
        bash -c "$command" > "$dump_file"
        echo "$dump_file"
        return $?
    }
    bash -c "$command"
}


function e5-delete-logs() {
    bash -c "$E5_CD_ROOT_DIR ; rm -rv 1CEduWeb/webapps/1CEduWeb/WEB-INF/log common/jetty/logs/*"
}
