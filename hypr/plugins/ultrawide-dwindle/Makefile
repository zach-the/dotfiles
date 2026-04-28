NAME   = ultrawide-dwindle
TARGET = $(NAME).so

CXX      = g++
CXXFLAGS = -shared -fPIC -std=c++23 -O2 \
           $(shell pkg-config --cflags hyprland) \
           -Wall -Wextra -Wno-unused-parameter

LDFLAGS  = $(shell pkg-config --libs hyprland)

$(TARGET): main.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $(TARGET) main.cpp

install: $(TARGET)
	install -Dm755 $(TARGET) $(HOME)/.config/hypr/plugins/$(TARGET)
	@echo "Add to hyprland.conf:  plugin = $(HOME)/.config/hypr/plugins/$(TARGET)"
	@echo "Set layout:            general { layout = ultrawide-dwindle }"

clean:
	rm -f $(TARGET)

.PHONY: install clean
