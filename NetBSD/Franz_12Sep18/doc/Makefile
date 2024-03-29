# Header: Makefile 1.4 83/07/21 21:27:16 sklower Exp
#	makefile for the franz lisp manual
#
# sources: lmacs: macros for the franz documents
#	   ch1.n  intro and description of types
#	   ch2.n  data structure access
#	   ch3.n  on arithmetic functions.
#	   ch4.n  special functions.
#	   ch5.n  i/o
#	   ch6.n  system functions
#	   ch7.n  reader
#	   ch8.n  functions and macros 
#	   ch9.n  arrays 
#	   ch10.n exception handling 
#	   ch11.n trace package 
#	   ch12.n liszt 
#	   ch13.n cmu top level
#	   ch14.n stepper 
#	   ch15.n fixit package
#	   ch16.n lisp editor
#	   chb.n special symbols
#	   chc.n  short subjects


.SUFFIXES: .n .t .x .v .r .rx .q .qx .sp

# the syntax's have this meaning:
#  .n  nroff/troff source file
#  .t  troff output file, can be vpr -t 'ed 
#  .x  index file from a troff run, when collected and run through troff
#	again, an index is produced.
#  .v  this file never exists, but asking for it will cause a .t file to
#	be created and then vpr'ed.  the .t file will not be deleted.
#  .p  this file also never exists, but asking for it will cause TROFF
#	(usually vtroff or itroff) to be run directly on the file, leaving
#	no .t around.  This is used in /usr/doc for people who want to
#	run off a manual and are too lazy to read this makefile.
#  .r  nroff output file.
#  .rx  special index output from nroff run.  These files should be catted
#       together and then left around for lisp to read when given the help
#	command.
#
#  .q  nroff output file compatible with model 37
#  .qx index file for .q files.
#
#  .sp spell errors
#
# make install will install the nroff versions of the manual in the
# directory (LibDir/manual) where the auxfns0.l help command can find them.
#
LibDir = /usr/lib/lisp
CcodeDir = ../franz
CopyTo = /dev/null
TROFF=	/usr/ucb/vtroff
NROFF=  nroff
O =
Append = ${LibDir}/append
# Rmt = is unecessary; you can say, make rall NROFF="'dali nroff'".
# better to just copy the doc directory to the remote machine and
# run it all there.

#--- Sources: 
#	We use the suffixes to tell make how to make a file.  Thus
#  we only specify the root and let the append function add the
#  appropriate suffix.

MacroSrc = lmacs

RootGenSrc = ch0 ch1 ch2 ch3 ch4 ch5 ch6 ch61 ch7 ch8 \
      ch9 ch10 ch11 ch12 ch13 ch14 ch15 ch16 ch17 chb chc

UtilSrc = Makefile indexsed mantags extrnames.awk fixmks.sed \
	franz.n

#-- can't get a expression for all source at make read time. must use
#   append to add .n to RootGenSrc


all:
	make rall

rall: ${Append}
	make NROFF=${NROFF} O=${O}  LibDir=${LibDir} \
		`${Append} .r ${RootGenSrc}` helpindex

vall: ${Append}
	make TROFF=${TROFF} O=${O} `${Append} .v ${RootGenSrc}` index.v

tall: ${Append}
	make TROFF=${TROFF} O=${O} `${Append} .t ${RootGenSrc}` index.t

cctall:
	make TROFF="troff -s12" tall

pall: ${Append}
	make TROFF=${TROFF} O=${O} `${Append} .p ${RootGenSrc}` pindex

troff: pall
	
qall: ${Append}
	make NROFF=${NROFF} O=${O} `${Append} .q ${RootGenSrc}` index.t

spall: ${Append}
	make TROFF=${TROFF} O=${O} `${Append} .q ${RootGenSrc}` index.t

# only a few files describe functions which are indexed.

.t.v:
	vpr -t $*.t

.n.t:	
	tbl lmacs $*.n | ${TROFF} -me ${O} -t 1> $*.t 2> $*.x

.n.p:
	tbl lmacs $*.n | ${TROFF} -me ${O} 2> $*.x

.n.x:
	tbl lmacs $*.n | ${TROFF} -me -z 2> $*.x

.n.r:
	tbl lmacs $*.n | ${NROFF} -rb3 -me ${O} 1> $*.r 2> $*.rx
	rm -f helpindex

.n.rx:
	tbl lmacs $*.n | ${NROFF} -rb3 -me 1> $*.r 2> $*.rx
	rm -f helpindex

.n.q:
	tbl lmacs $*.n | ${NROFF} -me -T37 2> $*.qx | col > $*.q

.n.sp:
	spell $*.n > $*.sp
	
install: 
#	make O=${O} rall
	make LibDir=${LibDir} rall
	cp `${Append} .r ${RootGenSrc}` helpindex ${LibDir}/manual

clean:
	-rm -f *.r 
	-rm -f *.rx 
	-rm -f helpindex 
	-rm -f *.t 
	-rm -f *.q 
	-rm -f *.x


findex:  ${Append}
	make `${Append} .x ${RootGenSrc}`
	echo ".Ib" > index
	sort +3 -o index index `${Append} .x ${RootGenSrc}`
	sed -f indexsed index > indexx 
	${Rmt} ${TROFF} -me lmacs indexx

index.t: 
	make `${Append} .x ${RootGenSrc}`
	echo ".Ib" > index
	sort +3 -o index index `${Append} .x ${RootGenSrc}`
	sed -f indexsed index > indexx
	${TROFF} -me -x -t lmacs indexx > index.t

pindex: ${Append}
	make `${Append} .x ${RootGenSrc}`
	echo ".Ib" > index
	sort +3 -o index index `${Append} .x ${RootGenSrc}`
	sed -f indexsed index > indexx
	${TROFF} -me lmacs indexx

helpindex: ${Append}
	make `${Append} .rx ${RootGenSrc}`
	cat `${Append} .rx ${RootGenSrc}` | tr '\227' ' ' > helpindex

tags:	/dev/tty ${Append}
	awk -f mantags `${Append} .n ${RootGenSrc}` | sort > tags


${Append}: 
	(cd ../utils  ; make LibDir=${LibDir} ${Append})

# to create a database for lxref to use:
C-database: ${CcodeDir}/sysat.c
	grep "^	MK" ${CcodeDir}/sysat.c > mks
	sed -f fixmks.sed < mks > mks.fixed
	(echo "(Chome)" ; cat mks.fixed ) > C-database
	rm -f mks mks.fixed

doc-database: 
	awk -f extrnames.awk `${Append} .n ${RootGenSrc}`\
 	   | sed -f fixmks.sed > doc-database


bigxref: C-database doc-database
	${Append} -p ${LibDir}/ `(cd ${LibDir} ; make echorequired)` | \
		sed 's/\.l/.x/g' > lisplibfiles
	lxref doc-database  C-database  `cat lisplibfiles` > bigxref

# simple table of contents, just a listing of which function is
# documented in which chapter
tofc:  
	egrep "^.Lc|^.Lf|^.Lx|^.sh" `${Append} .n  ${RootGenSrc}` > tofc


copysource:
	(tar cf - ${MacroSrc} `${Append} .n ${RootGenSrc}` ${UtilSrc} | \
	 (cd ${CopyTo} ; tar xf -))

scriptcatall: ${AllSrc} ${Append}
	@(cd .. ; scriptcat doc doc ${MacroSrc} `${Append} .n ${RootGenSrc}` ${UtilSrc})
	@(cd .. ; scriptcat doc lisplib/manual \
	      `${Append} .r ${RootGenSrc}` helpindex)

copymanual: ${Append} rall
	( cd ${FromDir}/manual ; \
	  cp `${Append} .r ${RootGenSrc}` helpindex ${CopyTo})


