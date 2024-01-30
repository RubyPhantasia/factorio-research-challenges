FACTORIO_PATH = C:/Program Files (x86)/Steam/steamapps/common/Factorio
FACTORIO_EXECUTABLE = $(FACTORIO_PATH)/bin/x64/factorio.exe
FACTORIO_DOCS_PATH = $(FACTORIO_PATH)/doc-html
RUNTIME_DOCS_PATH = $(FACTORIO_DOCS_PATH)/runtime-api.json
PROTOTYPE_DOCS_PATH = $(FACTORIO_DOCS_PATH)/prototype-api.json
MOD_ARG = --mod-directory
MOD_LOCATION = "$(abspath .)"

SUMNEKO_CMD = fmtk sumneko-3rd -d "$(RUNTIME_DOCS_PATH)" -p "$(PROTOTYPE_DOCS_PATH)" $(MOD_LOCATION)

runFactorio:
	"$(FACTORIO_EXECUTABLE)" $(MOD_ARG) $(MOD_LOCATION)

generateSumneko3rd:
	$(SUMNEKO_CMD)