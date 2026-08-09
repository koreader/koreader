DEBIAN_ARCH_x86_64 = amd64
DEBIAN_ARCH = $(or $(DEBIAN_ARCH_$(LINUX_ARCH)),$(LINUX_ARCH))
# v2025.10-197-g7c5ee9c1a2_2026-03-13 → 2025.10-197-g7c5ee9c1a2-1
DEBIAN_VERSION = $(word 1,$(subst _, ,$(VERSION:v%=%)))-1
DEBIAN_PACKAGE = koreader_$(DEBIAN_VERSION)_$(DEBIAN_ARCH).deb
DEBIAN_PACKAGE_COMPRESSION ?= -Zxz -z9

update-deb: all
	$(call mkupdate_linux,$(INSTALL_DIR)/deb)
	# Generate the package.
	$(LINUX_DIR)/do_debian_package.sh $(DEBIAN_PACKAGE) $(INSTALL_DIR)/deb $(DEBIAN_PACKAGE_COMPRESSION)
	# Cleanup.
	rm -rf $(INSTALL_DIR)/deb

update: update-deb
