#!/bin/bash
# Un montador de imágenes VDI de VirtualBox
# Juan M. Mouriz <jmouriz@gmail.com>

main()
{
	while getopts ':su:g:m:t:h' option; do
		case $option in
			s) test=1;;
			u) user=$OPTARG;;
			g) group=$OPTARG;;
			m) mode=$OPTARG;;
			t) type=$OPTARG;;
			h) usage;;
			:) error "La opción -$OPTARG necesita un argumento.";;
			?) error "Opción inválida: -$OPTARG.";;
		esac
	done

	shift $((OPTIND-1))

	if [ $# -lt 2 ]; then
		error "Faltan argumentos."
	elif [ $# -gt 2 ]; then
		error "Demasiados argumentos."
	fi
	
	image=$1
	target=$2

	for command in which id od awk mount; do
		check-command $command
	done

	check-root-user
	check-file "$image"
	check-folder "$target"
	check-image "$image"
	
	user=${user:-`id -un`}
	group=${group:-`id -gn`}
	mode=${mode:-rw}
	offdata=`get-offset-data "$image"`

	if [ -z "$type" ]; then
		fsid=`get-filesystem-id "$image" $offdata`
		type=`get-filesystem $fsid`
		check-filesystem $type
	fi

	let offset=$offdata+32256
	
	mount-image "$image" "$target" $type $user $group $mode $offset $test
}

usage()
{
	printf "$0 es un programa para montar imágenes VDI.\n"
	printf "\n"
	printf "Sintaxis: $0 [-s] [-u <usuario>] [-g <grupo>] [-m <modo>] [-t <tipo>] <imágen> <punto-montaje>\n"
	printf "\n"
	printf "\t<imágen>         La imágen VDI que quiere montar.\n"
	printf "\t<punto-montaje>  El punto de montaje donde quiere montar la imágen.\n"
	printf "\n"
	printf "\tTenga en cuenta que estos argumentos deben especificarse después que alguno de los siguientes modificadores:\n"
	printf "\n"
	printf "\t-s               Simulación. Muestra el comando a ejecutar pero no lo ejecuta.\n"
	printf "\t-u <usuario>     Especifica el usuario que tendrá acceso.\n"
	printf "\t                 Si se omite se considera el usuario que ejecutó el programa.\n"
	printf "\t-g <grupo>       Especifica el grupo que tendrá acceso.\n"
	printf "\t                 Si se omite se considera el grupo del usuario que ejecutó el programa.\n"
	printf "\t-m <modo>        Especifica el modo de accedso. Puede ser uno de:\n" 
	printf "\t\t                 rw  Acceso de lectura y escritura. El modo por omisión.\n"
	printf "\t\t                 ro  Acceso de sólo lectura.\n"
	printf "\t                 Si se omite se utilizará el modo de acceso de lectura y escritura.\n"
	printf "\t-t <tipo>        Especifica el tipo de sistema de archivos.\n"
	printf "\t                 Si se omite se intentará reconocerlo automáticamente.\n"
	printf "\t-h               Muestra la ayuda.\n"

	exit 0
}

error()
{
	printf "$*\n"
	exit 14
}

mount-image()
{
	if [ -z "$8" ]; then
		mount "$1" "$2" -t $3 -o uid=$4,gid=$5,$6,loop,offset=$7 2> /dev/null

		if [ "$?" != "0" ]; then
			printf "No se pudo montar la imágen.\n"
			# 1  incorrect invocation or permissions
			# 2  system error (out of memory, cannot fork, no more loop devices)
			# 4  internal mount bug
			# 8  user interrupt
			# 16 problems writing or locking /etc/mtab
			# 32 mount failure
			# 64 some mount succeeded
			exit 2
		fi
	else
		printf "mount '$1' '$2' -t $3 -o uid=$4,gid=$5,$6,loop,offset=$7\n"
	fi
}

check-root-user()
{
	id=`id -u`

	if [ "$id" != "0" ]; then
		printf "Debe ser 'root' para ejecutar este programa.\n"
		exit 1
	fi
}

check-command()
{
	which $* > /dev/null

	if [ "$?" != "0" ]; then
		printf "No se encontró el comando $*.\n"
		exit 2
	fi
}

check-param()
{
	if [ -z "$2" ]; then
		printf "Falta un parámetro: $1.\n"
		exit 3
	fi
}

check-file()
{
	if [ ! -f "$*" ]; then
		printf "No se encontró el archivo '$*'.\n"
		exit 4
	fi
}

check-folder()
{
	if [ ! -d "$*" ]; then
		printf "No se encontró el punto de montaje '$*'.\n"
		exit 5
	fi
}

check-image()
{
	image=$*

	variant=`od -j76 -N4 -td4 "$image" | awk 'NR==1 { print $2 }'`

	if [ "$variant" != "2" ]; then
		for command in mktemp rm mv dirname df VBoxManage grep cut sed tail; do
			check-command $command
		done

		tmp=`mktemp`

		VBoxManage showhdinfo "$image" > $tmp 2>&1

		if [ "$?" != "0" ]; then
			printf "La imágen no parece ser una imágen válida.\n"
			rm -f $tmp
			exit 6
		fi
		
		accessible=`grep ^Accessible $tmp | cut -d: -f2 | sed 's/^ *//g'`
		format=`grep ^Storage $tmp | cut -d: -f2 | sed 's/^ *//g'`
		size=`grep ^Logical $tmp | cut -d: -f2 | sed 's/^ *//g' | cut -d' ' -f1`
	
		rm -f $tmp
	
		if [ "$accessible" != "yes" ]; then
			printf "La imágen no parece ser una imágen accesible.\n"
			exit 7
		fi
	
		if [ "$format" != "VDI" ]; then
			printf "La imágen no debe ser una imágen VDI.\n"
			exit 8
		fi

		printf "La imágen no parece ser una imágen de tamano fijo.\n"

		read -p "Desea convertirla a una imágen de tamano fijo [S/n]? " -N1 response

		printf "\n"

		if [ "$response" != "S" ]; then
			exit 9
		fi

		location=`dirname "$image"`
		available=`df -B 1048576 "$location" | awk '{ print $4 }' | tail -1`

		if [ $available -lt $size ]; then
			printf "No queda espacio suficiente en el disco para convertir la imágen.\n"
			exit 10
		fi

		printf "Convirtiendo: "
			
		VBoxManage clonehd "$image" $tmp --format VDI --variant Fixed | grep ^0

		if [ "$id" != "0" ]; then
			printf "No se puede pudo convertir la imágen a una imágen de tamano fijo.\n"
			rm -f $tmp
			exit 11
		fi
			
		rm -f "$image"
		mv $tmp "$image"
	fi
}

check-filesystem()
{
	if [ "$*" == "unknown" ]; then
		printf "No se pudo reconocer el tipo de sistema de archivos de la imágen. Intente especificando uno.\n"
		exit 12
	fi
}

get-offset-data()
{
	od -j344 -N4 -td4 "$*" | awk 'NR==1 { print $2 }'
}

get-filesystem-id()
{
	for command in mktemp rm dd sfdisk grep head; do
		check-command $command
	done

	tmp=`mktemp`
	dd if="$*" of=$tmp bs=1 skip=$2 count=1b 2> /dev/null
	id=`sfdisk -luS $tmp 2> /dev/null | grep ^$tmp | head -1 | awk '{ print $6 }'`
	rm -f $tmp
	printf $id
}

get-filesystem()
{
	case "$*" in
		 0) printf "unknown" ;; # Vacía
		 1) printf "unknown" ;; # FAT12
		 2) printf "unknown" ;; # XENIX root
		 3) printf "unknown" ;; # XENIX usr
		 4) printf "unknown" ;; # FAT16 <32M
		 5) printf "unknown" ;; # Extendida
		 6) printf "unknown" ;; # FAT16
		 7) printf "ntfs"    ;; # HPFS/NTFS
		 8) printf "unknown" ;; # AIX
		 9) printf "unknown" ;; # AIX bootable
		 a) printf "unknown" ;; # OS/2 Boot Manager
		 b) printf "unknown" ;; # W95 FAT32
		 c) printf "unknown" ;; # W95 FAT32 (LBA)
		 e) printf "unknown" ;; # W95 FAT16 (LBA)
		 f) printf "unknown" ;; # W95 Ext'd (LBA)
		10) printf "unknown" ;; # OPUS
		11) printf "unknown" ;; # FAT12 oculta
		12) printf "unknown" ;; # Compaq diagnostics
		14) printf "unknown" ;; # FAT16 oculta <32M
		16) printf "unknown" ;; # FAT16 oculta
		17) printf "unknown" ;; # HPFS/NTFS oculta
		18) printf "unknown" ;; # SmartSleep de AST
		1b) printf "unknown" ;; # Hidden W95 FAT32
		1c) printf "unknown" ;; # Hidden W95 FAT32 (LBA)
		1e) printf "unknown" ;; # Hidden W95 FAT16 (LBA)
		24) printf "unknown" ;; # NEC DOS
		39) printf "unknown" ;; # Plan 9
		3c) printf "unknown" ;; # PartitionMagic recovery
		40) printf "unknown" ;; # Venix 80286
		41) printf "unknown" ;; # PPC PReP Boot
		42) printf "unknown" ;; # SFS
		4d) printf "unknown" ;; # QNX4.x
		4e) printf "unknown" ;; # QNX4.x segunda parte
		4f) printf "unknown" ;; # QNX4.x tercera parte
		50) printf "unknown" ;; # OnTrack DM
		51) printf "unknown" ;; # OnTrack DM6 Aux1
		52) printf "unknown" ;; # CP/M
		53) printf "unknown" ;; # OnTrack DM6 Aux3
		54) printf "unknown" ;; # OnTrackDM6
		55) printf "unknown" ;; # EZ-Drive
		56) printf "unknown" ;; # Golden Bow
		5c) printf "unknown" ;; # Priam Edisk
		61) printf "unknown" ;; # SpeedStor
		63) printf "unknown" ;; # GNU HURD o SysV
		64) printf "unknown" ;; # Novell Netware 286
		65) printf "unknown" ;; # Novell Netware 386
		70) printf "unknown" ;; # DiskSecure Multi-Boot
		75) printf "unknown" ;; # PC/IX
		80) printf "unknown" ;; # Old Minix
		81) printf "unknown" ;; # Minix / old Linux
		82) printf "unknown" ;; # Linux swap / Solaris
		83) printf "unknown" ;; # Linux
		84) printf "unknown" ;; # Unidad C: oculta de OS/2
		85) printf "unknown" ;; # Linux extendida
		86) printf "unknown" ;; # Conjunto de volúmenes NTFS
		87) printf "unknown" ;; # Conjunto de volúmenes NTFS
		88) printf "unknown" ;; # Linux plaintext
		8e) printf "unknown" ;; # Linux LVM
		93) printf "unknown" ;; # Amoeba
		94) printf "unknown" ;; # Amoeba BBT
		9f) printf "unknown" ;; # BSD/OS
		a0) printf "unknown" ;; # Hibernación de IBM Thinkpad
		a5) printf "unknown" ;; # FreeBSD
		a6) printf "unknown" ;; # OpenBSD
		a7) printf "unknown" ;; # NeXTSTEP
		a8) printf "unknown" ;; # UFS de Darwin
		a9) printf "unknown" ;; # NetBSD
		ab) printf "unknown" ;; # arranque de Darwin
		af) printf "unknown" ;; # HFS / HFS+
		b7) printf "unknown" ;; # BSDI fs
		b8) printf "unknown" ;; # BSDI swap
		bb) printf "unknown" ;; # Boot Wizard hidden
		be) printf "unknown" ;; # arranque de Solaris
		bf) printf "unknown" ;; # Solaris
		c1) printf "unknown" ;; # DRDOS/sec (FAT-12)
		c4) printf "unknown" ;; # DRDOS/sec (FAT-16 < 32M)
		c6) printf "unknown" ;; # DRDOS/sec (FAT-16)
		c7) printf "unknown" ;; # Syrinx
		da) printf "unknown" ;; # Datos sin SF
		db) printf "unknown" ;; # CP/M / CTOS / ...
		de) printf "unknown" ;; # Utilidad Dell
		df) printf "unknown" ;; # BootIt
		e1) printf "unknown" ;; # DOS access
		e3) printf "unknown" ;; # DOS R/O
		e4) printf "unknown" ;; # SpeedStor
		eb) printf "unknown" ;; # BeOS fs
		ee) printf "unknown" ;; # GPT
		ef) printf "unknown" ;; # EFI (FAT-12/16/32)
		f0) printf "unknown" ;; # inicio Linux/PA-RISC
		f1) printf "unknown" ;; # SpeedStor
		f4) printf "unknown" ;; # SpeedStor
		f2) printf "unknown" ;; # DOS secondary
		fb) printf "unknown" ;; # VMware VMFS
		fc) printf "unknown" ;; # VMware VMKCORE
		fd) printf "unknown" ;; # Linux raid autodetect
		fe) printf "unknown" ;; # LANstep
		ff) printf "unknown" ;; # BBT
		 *) printf "unknown" ;; # No se pudo determinar
	esac
}

IFS='|'
main $*

exit 0
