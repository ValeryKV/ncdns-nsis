MAKENSIS ?= makensis
NSISFLAGS ?= -V2

NCDNS_REPO ?= github.com/namecoin/ncdns
NCDNS_PRODVER ?= 
ifeq ($(NCDNS_PRODVER),)
	ifneq ($(GOPATH),)
		NCDNS_PRODVER=$(shell git -C "$(GOPATH)/src/$(NCDNS_REPO)" describe --all --abbrev=99 |grep -E '^v[0-9]')
	endif
endif
ifeq ($(NCDNS_PRODVER),)
	NCDNS_PRODVER=0.0.0
endif

NCDNS_PRODVER_W=$(shell echo "$(NCDNS_PRODVER)" | sed 's/^v//' | sed 's/$$/.0/')

_NO_NAMECOIN_CORE=
ifeq ($(NO_NAMECOIN_CORE),1)
	_NO_NAMECOIN_CORE=-DNO_NAMECOIN_CORE
endif

_NO_DNSSEC_TRIGGER=
ifeq ($(NO_DNSSEC_TRIGGER),1)
	_NO_DNSSEC_TRIGGER=-DNO_DNSSEC_TRIGGER
endif

_NCDNS_64BIT=
_BUILD=build32
GOARCH=386
BINDARCH=x86
ifeq ($(NCDNS_64BIT),1)
	_NCDNS_64BIT=-DNCDNS_64BIT=1
	_BUILD=build64
	GOARCH=amd64
	BINDARCH=x64
endif
BUILD ?= $(_BUILD)

NEUTRAL_ARTIFACTS = artifacts
ARTIFACTS = $(BUILD)/artifacts

NCARCH=win32
ifeq ($(NCDNS_64BIT),1)
  NCARCH=win64
endif
OUTFN := $(BUILD)/bin/ncdns-$(NCDNS_PRODVER)-$(NCARCH)-install.exe

all: $(OUTFN)


### NCDNS
##############################################################################
NCDNS_ARCFN=ncdns-$(NCDNS_PRODVER)-windows_$(GOARCH).tar.gz

$(ARTIFACTS)/$(NCDNS_ARCFN):
	mkdir -p "$(ARTIFACTS)"
	wget -O "$@" "https://github.com/namecoin/ncdns/releases/download/$(NCDNS_PRODVER)/$(NCDNS_ARCFN)"

EXES=ncdns ncdumpzone generate_nmc_cert ncdt tlsrestrict_chromium_tool
EXES_A=$(foreach k,$(EXES),$(ARTIFACTS)/$(k).exe)

$(ARTIFACTS)/ncdns.exe: $(ARTIFACTS)/$(NCDNS_ARCFN)
	(cd "$(ARTIFACTS)"; tar zxvf "$(NCDNS_ARCFN)"; mv ncdns-$(NCDNS_PRODVER)-windows_$(GOARCH)/bin/* ./; rm -rf ncdns-$(NCDNS_PRODVER)-windows_$(GOARCH);)


### DNSSEC-KEYGEN
##############################################################################
BINDV=9.12.1
$(ARTIFACTS)/BIND$(BINDV).$(BINDARCH).zip:
	wget -O "$@" "https://ftp.isc.org/isc/bind/$(BINDV)/BIND$(BINDV).$(BINDARCH).zip"

KGFILES=dnssec-keygen.exe libisc.dll libdns.dll libeay32.dll libxml2.dll
KGFILES_T=$(foreach k,$(KGFILES),tmp/$(k))
KGFILES_A=$(foreach k,$(KGFILES),$(ARTIFACTS)/$(k))

$(ARTIFACTS)/dnssec-keygen.exe: $(ARTIFACTS)/BIND$(BINDV).$(BINDARCH).zip
	(cd "$(ARTIFACTS)"; mkdir tmp; cd tmp; unzip "../BIND$(BINDV).$(BINDARCH).zip"; cd ..; mv $(KGFILES_T) .; rm -rf tmp;)

.NOTPARALLEL: $(KGFILES_A)


### DNSSEC-TRIGGER
##############################################################################
DNSSEC_TRIGGER_VER=0.15
DNSSEC_TRIGGER_FN=dnssec_trigger_setup_$(DNSSEC_TRIGGER_VER).exe
DNSSEC_TRIGGER_URL=https://www.nlnetlabs.nl/downloads/dnssec-trigger/
#DNSSEC_TRIGGER_URL=https://www.nlnetlabs.nl/~wouter/

$(ARTIFACTS)/$(DNSSEC_TRIGGER_FN):
	wget -O "$@" "$(DNSSEC_TRIGGER_URL)$(DNSSEC_TRIGGER_FN)"


### NAMECOIN
##############################################################################
NAMECOIN_VER=0.13.99
NAMECOIN_VER_TAG=-name-tab-beta1-notreproduced
NAMECOIN_FN=namecoin-$(NAMECOIN_VER)-$(NCARCH)-setup-unsigned.exe

$(ARTIFACTS)/$(NAMECOIN_FN):
	wget -O "$@" "https://namecoin.org/files/namecoin-core-$(NAMECOIN_VER)$(NAMECOIN_VER_TAG)/$(NAMECOIN_FN)"


### Q
##############################################################################
$(ARTIFACTS)/q.exe:
	(cd "$(ARTIFACTS)"; GOOS=windows GOARCH=$(GOARCH) go build github.com/miekg/exdns/q;)

### INSTALLER
##############################################################################
$(OUTFN): ncdns.nsi $(NEUTRAL_ARTIFACTS)/ncdns.conf $(EXES_A) $(KGFILES_A) $(ARTIFACTS)/$(DNSSEC_TRIGGER_FN) $(ARTIFACTS)/$(NAMECOIN_FN) $(ARTIFACTS)/q.exe
	@mkdir -p "$(BUILD)/bin"
	$(MAKENSIS) $(NSISFLAGS) -DPOSIX_BUILD=1 -DNCDNS_PRODVER=$(NCDNS_PRODVER_W) \
		$(_NCDNS_64BIT) $(_NO_NAMECOIN_CORE) $(_NO_DNSSEC_TRIGGER) \
		-DARTIFACTS=$(BUILD)/artifacts \
		-DNEUTRAL_ARTIFACTS=artifacts \
		-DDNSSEC_TRIGGER_FN=$(DNSSEC_TRIGGER_FN) \
		-DNAMECOIN_FN=$(NAMECOIN_FN) \
		-DOUTFN="$(OUTFN)" "$<"

clean:
	rm -rf "$(BUILD)"
