#####################

DEBUG =

SOURCES_BASE = reader.fs printer.fs types.fs functions.fs # error.fs node.fs tokenizer.fs \
	       readline.fs
SOURCES_LISP = core.fs #env.fs stepA_mal.fs
SOURCES = $(SOURCES_BASE) $(SOURCES_LISP)

TERMINAL_SOURCES = terminal.cs

#####################

SRCS = step0_repl.fs step1_read_print.fs step2_eval.fs step3_env.fs \
       step4_if_fn_do.fs step5_tco.fs step6_file.fs step7_quote.fs \
       step8_macros.fs step9_try.fs stepA_mal.fs
DLL_SOURCES = $(filter-out stepA_mal.fs,$(SOURCES))

FSFLAGS = $(if $(strip $(DEBUG)),--debug+,--debug- --optimize+ --tailcalls+)
CSFLAGS = $(if $(strip $(DEBUG)),-debug+,)
#####################

all: $(patsubst %.fs,%.exe,$(SRCS))

dist: mal.exe mal

mal.exe: stepA_mal.exe
	cp $< $@

# NOTE/WARNING: static linking triggers mono libraries LGPL
# distribution requirements.
# http://www.mono-project.com/archived/guiderunning_mono_applications/
mal: $(patsubst %.fs,%.exe,$(word $(words $(SOURCES)),$(SOURCES))) Mono.Terminal.dll mal.dll
	mkbundle --static -o $@ $+ --deps

Mono.Terminal.dll: $(TERMINAL_SOURCES)
	mcs $(CSFLAGS) -target:library $+ -out:$@

mal.dll: $(DLL_SOURCES) Mono.Terminal.dll
	fsharpc $(FSFLAGS) -o $@ -r Mono.Terminal.dll -a $(DLL_SOURCES)

%.exe: %.fs mal.dll
	fsharpc $(FSFLAGS) -o $@ -r mal.dll $<

clean:
	rm -f mal *.dll *.exe *.mdb
