MODULE_NAME=Public.Template.Mustache
MODULE_LICENSE=GPL/LGPL/MPL
MODULE_DIR_NAME=Public_Template_Mustache
AUTHOR=William Welliver <william@welliver.org>

release: 
	if [ "X${MIN}" == "X" ] ; then echo "No version provided."; exit 1; fi
	hg tag -fr tip RELEASE_1.${MIN}
	hg push
	hg archive -r RELEASE_1.${MIN} ${MODULE_DIR_NAME}-1.${MIN}
	rm ${MODULE_DIR_NAME}-1.${MIN}/Makefile
	rm ${MODULE_DIR_NAME}-1.${MIN}/upload_module_version.pike 
	pike -x rsif -r "@@version@@" "1.${MIN}" ${MODULE_DIR_NAME}-1.${MIN}
	pike -x rsif -r "@@author@@" "${AUTHOR}" ${MODULE_DIR_NAME}-1.${MIN}
	echo "MODULE=${MODULE_NAME}" > ${MODULE_DIR_NAME}-1.${MIN}/METADATA.TXT
	echo "VERSION=1.${MIN}" >> ${MODULE_DIR_NAME}-1.${MIN}/METADATA.TXT
	echo "PLATFORM=any/any" >> ${MODULE_DIR_NAME}-1.${MIN}/METADATA.TXT
	tar cvf ${MODULE_DIR_NAME}-1.${MIN}.tar ${MODULE_DIR_NAME}-1.${MIN}
	gzip ${MODULE_DIR_NAME}-1.${MIN}.tar
	rm -rf ${MODULE_DIR_NAME}-1.${MIN}
	pike upload_module_version.pike ${MODULE_NAME} 1.${MIN} "${MODULE_LICENSE}"
