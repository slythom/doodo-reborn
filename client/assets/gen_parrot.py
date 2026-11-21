import zlib, struct, sys

# Palette
PAL = {
    'R': (230, 60, 45, 255),    # rouge ara
    'r': (180, 45, 35, 255),    # rouge ombré
    'W': (250, 240, 222, 255),  # joue crème
    'B': (238, 224, 198, 255),  # bec ivoire
    'k': (42, 38, 40, 255),     # bec noir / contour
    'E': (28, 24, 28, 255),     # œil
    'Y': (245, 196, 60, 255),   # jaune aile
    'G': (52, 168, 88, 255),    # vert aile
    'U': (54, 126, 196, 255),   # bleu queue/aile
    'f': (92, 70, 54, 255),     # pattes
}

MAP = [
"........RRRRR...........",
"......RRRRRRRRR.........",
".....RRRRRRRRRRR........",
"....RRRWWERRRRRr........",
"...BBRRWERRRRRRr........",
"..BBBBRWWRRRRRr.........",
"...BBkRRRRRRRRr.........",
".....RRRRRRRRRr.........",
"....RRRRRRRRRRr.........",
"...RRRRRGGGRRRRr.........",
"..RRRRGGYYYGRRRr.........",
"..RRRRGGYYYYYGRRr........",
"..RRRGYYYYYYUGRr.........",
"..RRGGYYYYUUUGRr.........",
"..RRGYYYYUUUUURr.........",
"..RRGGYYUUUUURRr.........",
"...RRGUUUUUUURRr.........",
"....RRUUUUUURRR..........",
".....RUUUURff...........",
".....RUUUR.fff..........",
".....RUUR...............",
"....RUUUR...............",
"....RUUR................",
"...RUUR.................",
]

W = len(MAP[0]); H = len(MAP)
SCALE = 4
px = [[ (0,0,0,0) for _ in range(W)] for _ in range(H)]
for y, row in enumerate(MAP):
    for x, ch in enumerate(row):
        if ch != '.':
            px[y][x] = PAL[ch]

def png(path, w, h, get):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            raw += bytes(get(x, y))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c))
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', ihdr)
        + chunk(b'IDAT', zlib.compress(raw, 9))
        + chunk(b'IEND', b''))

png(sys.argv[1], W*SCALE, H*SCALE, lambda x, y: px[y//SCALE][x//SCALE])
print("ok", W*SCALE, H*SCALE)
