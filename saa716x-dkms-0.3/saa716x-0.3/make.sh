#!/bin/bash
# Based on mk_dvb_kernel_modules.sh from:
# https://martinkg.fedorapeople.org/DVB-S2-Driver/

# logging to both the console and the log files
function print() { if [ "$logfile" ]; then echo -e "$@" | tee -a "$logfile"; else echo -e "$@"; fi; [ x$2 = x ] || exit $2; }

# check for root privileges
[ x$(whoami) = xroot ] || print "Script must be run with root privileges" 1

# options and parameters
while [ "$1" ]; do
    case "$1" in
    -b|--batch)         batch=1;
                        shift;;
    -c|--clean)         clean=1;
                        shift;;
    -d|--dest)          [ "$2" ] && dest=$(realpath "$2");
                        shift 2;;
    -h|--help)          help=1;
                        shift;;
    -k|--kernel)        [ "$2" ] && kernel="$2";
                        shift 2;;
    -l|--logfile)       [ "$2" ] && logfile="$(realpath "$2")";
                        shift 2;;
    -s|--source)        [ "$2" ] && source="$(realpath "$2")";
                        shift 2;;
    *)                  shift;;
    esac
done

# print the help message
if [ "$help" ]; then
    echo -e "\nUsage: $(basename "$0") [options]"
    echo -e "\nBuilds the kernel modules for the SAA716X DVB-S2 device, either for the"
    echo -e "current kernel ($(uname -r)) or a specific other kernel."
    echo -e "\nOptions:"
    echo -e "-b|--batch         suppress any user interaction"
    echo -e "-c|--clean         clean all source code building"
    echo -e "-d|--dest dir      copy the modules to a specific directory"
    echo -e "-h|--help          print this help information"
    echo -e "-k|--kernel name   build for a specific kernel, format like 'uname -r'"
    echo -e "-l|--logfile log   print diagnostics in a specific file"
    echo -e "-s|--source dir    build in a specific directory"
    echo -e "\nIf no destination directory is specified, the kernel modules will be"
    echo -e "installed in the kernel's regular module tree."
    echo -e
    exit 1
fi

# determine the kernel parameters
[ "$source" ] || source=$(pwd)
[ "$kernel" ] || kernel=$(uname -r)
release=$(echo $kernel | egrep -o "^[0-9]+\\.[0-9]+")
archive=saa716x-$release
modules=drivers/media/pci/saa716x
patches=$source/saa716x.diff

# initiate the logging
[ "$logfile" ] && >$logfile

# start the build
print "Building for kernel $release ($kernel)"

# clean the sources and exit if requested by an option
if [ -z "$clean" ]; then
    if [ -z "$batch" ] && [ -f $source/$archive.zip -o -d $source/$archive ]; then
        echo -e "\nClean all before building (y/N)?"
        read choice
        [ "${choice//Y/y}" = "y" ] && clean=1
        echo
    fi
    if [ "$clean" ]; then
        print "Cleaning the source tree"
        rm -f  $source/$archive.zip >/dev/null 2>&1
        rm -fr $source/$archive >/dev/null 2>&1
    fi
else
    print "Cleaning the source tree"
    rm -f  $source/$archive.zip >/dev/null 2>&1
    rm -fr $source/$archive >/dev/null 2>&1
    exit 0
fi

# download the driver source
if [ ! -f $source/$archive.zip ]; then
    print "Downloading saa716x-$release.zip"
    wget -O $source/$archive.zip https://github.com/s-moch/linux-saa716x/archive/$archive.zip || print "Download failed" 1
    rm -rf $source/$archive >/dev/null 2>&1
fi

# patch the driver source
if [ ! -d $source/$archive ]; then
    print "Unpacking $archive.zip"
    unzip -q $source/$archive.zip
    mv $source/linux-saa716x-$archive $archive
    print "Copying header files to driver directory"
    headers=(\
        $source/$archive/drivers/media/dvb-frontends/isl6423.h \
        $source/$archive/drivers/media/dvb-frontends/mb86a16.h \
        $source/$archive/drivers/media/dvb-frontends/si2168.h \
        $source/$archive/drivers/media/dvb-frontends/stv090x.h \
        $source/$archive/drivers/media/dvb-frontends/stv6110x.h \
        $source/$archive/drivers/media/dvb-frontends/tda1004x.h \
        $source/$archive/drivers/media/dvb-frontends/zl10353.h \
        $source/$archive/drivers/media/tuners/si2157.h \
        $source/$archive/drivers/media/tuners/tda18271.h \
        $source/$archive/drivers/media/tuners/tda827x.h \
        $source/$archive/drivers/media/tuners/tda8290.h \
   )
    cp ${headers[@]} $source/$archive/$modules || print "Copying header files failed" 1
    cd $source/$archive/$modules
    patch -p1 -i $patches || print "Patching source files failed" 1
    cd -
fi

# build the driver
print "Building the driver"
cd $source/$archive/$modules
make KDIR=/lib/modules/$kernel/build clean
make KDIR=/lib/modules/$kernel/build || print "Make failed" 1
cd -

# publish or install the modules
if [ "$dest" ]; then
    print "Publishing the kernel modules to $dest:\n$(cd $source/$archive/$modules; ls -l *.ko)"
    mkdir -p $dest
    cp -f $source/$archive/$modules/*.ko $dest
else
    dest=/lib/modules/$kernel
    print "Installing the kernel modules to $dest:\n$(cd "$source/$archive/$modules"; ls -l *.ko)"
    mkdir -p $dest/$kernel/$modules
    cp -f $source/$archive/$modules/*.ko $dest/$kernel/$modules
    print "Updating the kernel-module dependencies"
    depmod -a
fi

# exit the script
print "SAA761X DVB-S2 modules built"
exit 0
