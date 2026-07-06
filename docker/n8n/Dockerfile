# Docker Hardened n8n-Image hat keinen Paketmanager (weder Build- noch Laufzeit).
# Chromium + Laufzeit-Bibliotheken werden daher aus einem regulären Alpine-Image
# geholt und additiv nach /opt/chromium kopiert (kein Overwrite von /usr/lib des
# n8n-Basisimages, um vorhandene Libraries wie GraphicsMagick/curl nicht zu brechen).

FROM alpine:3.22 AS chromium-source
RUN apk add --no-cache chromium nss freetype harfbuzz ca-certificates ttf-freefont

FROM n8nio/n8n:2.27.3

USER root

# Alle von Alpine für chromium+deps installierten Dateien 1:1 nach /opt/chromium-root
# spiegeln (additiv, eigener Präfix, überschreibt nichts im n8n-Image).
COPY --from=chromium-source /usr/lib/chromium /opt/chromium-root/usr/lib/chromium
COPY --from=chromium-source /usr/bin/chromium-browser /opt/chromium-root/usr/bin/chromium-browser
COPY --from=chromium-source /usr/lib/ /opt/chromium-root/usr/lib/
COPY --from=chromium-source /lib/ /opt/chromium-root/lib/
COPY --from=chromium-source /usr/share/fonts /usr/share/fonts
COPY --from=chromium-source /etc/chromium /etc/chromium

ENV LD_LIBRARY_PATH=/opt/chromium-root/usr/lib:/opt/chromium-root/usr/lib/pulseaudio:/opt/chromium-root/lib
ENV PATH=/opt/chromium-root/usr/lib/chromium:$PATH
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/opt/chromium-root/usr/lib/chromium/chromium

USER node
