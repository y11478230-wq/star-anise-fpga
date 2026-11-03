// PYNQ-Z1 frame-based image pipeline accelerator.
// Algorithm source of truth: ../reference/board_vision_algorithms.py
// This kernel reads one 640x480 RGB565 camera frame from DDR, builds the
// 1280x640 six-panel mosaic in DDR, and returns the stable tip count.
#include <ap_int.h>
#include <hls_math.h>
#include <stdint.h>

static const int IN_W = 640, IN_H = 480;
static const int W = 160, H = 120, N = W * H;
static const int PANEL_W = 320, PANEL_H = 240, PANEL_N = PANEL_W * PANEL_H;
static const int OUT_W = 1280, OUT_H = 640;
static const int HIST = 5, TIP_HIST = 9, MAX_TIPS = 32;

struct RGB { uint8_t r, g, b; };
struct HSV { uint8_t h, s, v; };
// Point coordinates are Q8 fixed-point pixels.
struct Point { int32_t x, y; };

// Large frame-working arrays are passed into helper functions as views over a
// caller-provided DDR scratch buffer. Static global pointers are unsupported by
// Vitis HLS and would otherwise infer oversized on-chip memories.
static int32_t radial[360], smooth_radial[360];
static int32_t current_scale = 256;
static uint16_t peak_bins[360];
static int32_t peak_prom[360];
static uint16_t radial_x[360], radial_y[360];
static ap_uint<1> radial_valid[360];
static Point current_tips[MAX_TIPS];
static Point history_tips[TIP_HIST][MAX_TIPS];
static uint8_t history_tip_counts[TIP_HIST];
static uint8_t history_tip_valid[TIP_HIST];
static uint32_t fill_frame_index = 0;
static uint8_t fill_history_count = 0;
static uint8_t tip_history_count = 0;
static uint8_t tip_history_write = 0;
static bool detector_source_initialized = false;
static bool previous_dark_detector = false;

// Workspace layout in panel_workspace (all offsets are ap_uint<32> words).
// Full-frame working sets live in DDR scratch instead of oversized BRAM arrays.
static const int SCRATCH_WORDS = N + 1;

// Frequently reused working frames stay in block RAM. Only component labels,
// the flood queue/statistics and the six display tiles use the external DDR
// scratch buffer.
// The large RGB frames live in the caller-provided DDR workspace. Keeping
// three 160x120 RGB frames in BRAM consumes most of the XC7Z020 block RAM.
static uint8_t gray_buf[N], blur_buf[N];
static ap_uint<1> mask_a_buf[N], mask_b_buf[N];
static ap_uint<2> edge_buf[N];
static int16_t gx_buf[N], gy_buf[N];
static uint16_t mag_buf[N];
// Keep the repeatedly sampled bilateral source in BRAM; stable and denoised
// frames are in DDR to keep the total block-RAM footprint below device limits.
static ap_uint<32> corrected_buf[N];

static inline uint8_t clip8(int value) {
#pragma HLS INLINE
    return value < 0 ? 0 : (value > 255 ? 255 : (uint8_t)value);
}

// Exact floor(n / d) for the small variable divisors used by RGB/HSV math.
// A Q24 reciprocal ROM replaces the large general-purpose divider; the
// remainder correction keeps the result bit-exact for n <= 65535.
static inline uint16_t div_u16_u8(uint16_t n, uint8_t d) {
#pragma HLS INLINE
    static const uint32_t reciprocal_q24[256] = { 0,16777216,8388608,5592405,4194304,3355443,2796202,2396745,2097152,1864135,1677721,1525201,1398101,1290555,1198372,1118481,1048576,986895,932067,883011,838860,798915,762600,729444,699050,671088,645277,621378,599186,578524,559240,541200,524288,508400,493447,479349,466033,453438,441505,430185,419430,409200,399457,390167,381300,372827,364722,356962,349525,342392,335544,328965,322638,316551,310689,305040,299593,294337,289262,284359,279620,275036,270600,266305,262144,258111,254200,250406,246723,243148,239674,236298,233016,229824,226719,223696,220752,217885,215092,212369,209715,207126,204600,202135,199728,197379,195083,192841,190650,188508,186413,184365,182361,180400,178481,176602,174762,172960,171196,169466,167772,166111,164482,162885,161319,159783,158275,156796,155344,153919,152520,151146,149796,148470,147168,145888,144631,143395,142179,140985,139810,138654,137518,136400,135300,134217,133152,132104,131072,130055,129055,128070,127100,126144,125203,124275,123361,122461,121574,120699,119837,118987,118149,117323,116508,115704,114912,114130,113359,112598,111848,111107,110376,109655,108942,108240,107546,106861,106184,105517,104857,104206,103563,102927,102300,101680,101067,100462,99864,99273,98689,98112,97541,96978,96420,95869,95325,94786,94254,93727,93206,92691,92182,91678,91180,90687,90200,89717,89240,88768,88301,87838,87381,86928,86480,86037,85598,85163,84733,84307,83886,83468,83055,82646,82241,81840,81442,81049,80659,80273,79891,79512,79137,78766,78398,78033,77672,77314,76959,76608,76260,75915,75573,75234,74898,74565,74235,73908,73584,73262,72944,72628,72315,72005,71697,71392,71089,70789,70492,70197,69905,69615,69327,69042,68759,68478,68200,67923,67650,67378,67108,66841,66576,66313,66052,65793 };
    if (d == 0) return 0;
    // The Q24 reciprocal multiplication needs up to 40 bits. Truncating it
    // to 32 bits before the shift wraps high gains and corrupts dark pixels.
    uint32_t q = (uint32_t)(((uint64_t)n * reciprocal_q24[d]) >> 24);
    if ((uint32_t)n - q * d >= d) ++q;
    return (uint16_t)q;
}

static inline RGB rgb565_to_rgb(uint16_t p) {
#pragma HLS INLINE
    RGB c;
    uint8_t r5 = (p >> 11) & 31, g6 = (p >> 5) & 63, b5 = p & 31;
    c.r = (uint16_t)r5 * 255 / 31;
    c.g = (uint16_t)g6 * 255 / 63;
    c.b = (uint16_t)b5 * 255 / 31;
    return c;
}

static inline RGB sampled_rgb(const ap_uint<16> *frame, int x, int y) {
#pragma HLS INLINE
    RGB a=rgb565_to_rgb(frame[(4*y+0)*IN_W+4*x+0]);
    RGB b=rgb565_to_rgb(frame[(4*y+0)*IN_W+4*x+2]);
    RGB c=rgb565_to_rgb(frame[(4*y+2)*IN_W+4*x+0]);
    RGB d=rgb565_to_rgb(frame[(4*y+2)*IN_W+4*x+2]);
    RGB q;
    q.r=(uint8_t)((a.r+b.r+c.r+d.r+2)>>2);
    q.g=(uint8_t)((a.g+b.g+c.g+d.g+2)>>2);
    q.b=(uint8_t)((a.b+b.b+c.b+d.b+2)>>2);
    return q;
}

static inline uint16_t rgb_to_565(RGB c) {
#pragma HLS INLINE
    return ((uint16_t)(c.r >> 3) << 11) | ((uint16_t)(c.g >> 2) << 5) |
           (uint16_t)(c.b >> 3);
}

static inline ap_uint<32> pack_rgb(RGB c) {
#pragma HLS INLINE
    return ((ap_uint<32>)c.r << 16) | ((ap_uint<32>)c.g << 8) | c.b;
}

static inline RGB unpack_rgb(ap_uint<32> p) {
#pragma HLS INLINE
    RGB c = {(uint8_t)(p >> 16), (uint8_t)(p >> 8), (uint8_t)p};
    return c;
}

static inline HSV rgb_to_hsv(RGB c) {
#pragma HLS INLINE
    HSV o;
    uint8_t mx = c.r > c.g ? (c.r > c.b ? c.r : c.b) : (c.g > c.b ? c.g : c.b);
    uint8_t mn = c.r < c.g ? (c.r < c.b ? c.r : c.b) : (c.g < c.b ? c.g : c.b);
    int d = (int)mx - (int)mn;
    o.v = mx;
    o.s = mx == 0 ? 0 : (uint8_t)div_u16_u8((uint16_t)(d * 255 + mx / 2), mx);
    if (d == 0) o.h = 0;
    else {
        int num;
        if (mx == c.r) num = 30 * ((int)c.g - (int)c.b);
        else if (mx == c.g) num = 30 * ((int)c.b - (int)c.r) + 60 * d;
        else num = 30 * ((int)c.r - (int)c.g) + 120 * d;
        if (num < 0) num += 180 * d;
        int hi = div_u16_u8((uint16_t)(num + d / 2), (uint8_t)d);
        o.h = (uint8_t)(hi >= 180 ? hi - 180 : hi);
    }
    return o;
}

static inline RGB hsv_to_rgb(HSV c) {
#pragma HLS INLINE
    int sector = c.h / 30;
    int frac = c.h - sector * 30;
    int v = c.v, s = c.s;
    int p = (v * (255 - s) + 127) / 255;
    int q = (v * (255 * 30 - s * frac) + 127 * 30) / (255 * 30);
    int t = (v * (255 * 30 - s * (30 - frac)) + 127 * 30) / (255 * 30);
    RGB o;
    if (sector == 0) { o.r=v; o.g=t; o.b=p; }
    else if (sector == 1) { o.r=q; o.g=v; o.b=p; }
    else if (sector == 2) { o.r=p; o.g=v; o.b=t; }
    else if (sector == 3) { o.r=p; o.g=q; o.b=v; }
    else if (sector == 4) { o.r=t; o.g=p; o.b=v; }
    else { o.r=v; o.g=p; o.b=q; }
    return o;
}

static inline int reflect101(int p, int limit) {
#pragma HLS INLINE
    if (p < 0) return -p;
    if (p >= limit) return 2 * limit - p - 2;
    return p;
}

static inline RGB get_rgb(const ap_uint<32> *src, int x, int y) {
#pragma HLS INLINE
    x = reflect101(x, W); y = reflect101(y, H);
    return unpack_rgb(src[y * W + x]);
}

static inline uint8_t get_u8(const uint8_t *src, int x, int y) {
#pragma HLS INLINE
    x = reflect101(x, W); y = reflect101(y, H);
    return src[y * W + x];
}

static inline void panel_write(ap_uint<32> *work, int panel, int x, int y, RGB c) {
#pragma HLS INLINE
    if (x >= 0 && x < PANEL_W && y >= 0 && y < PANEL_H)
        work[panel * PANEL_N + y * PANEL_W + x] =
            ((uint32_t)c.r << 16) | ((uint32_t)c.g << 8) | c.b;
}

static RGB panel_read(const ap_uint<32> *work, int panel, int x, int y) {
#pragma HLS INLINE
    if (x < 0) x = 0; if (x >= PANEL_W) x = PANEL_W - 1;
    if (y < 0) y = 0; if (y >= PANEL_H) y = PANEL_H - 1;
    uint32_t q = work[panel * PANEL_N + y * PANEL_W + x];
    RGB c = {(uint8_t)(q >> 16), (uint8_t)(q >> 8), (uint8_t)q};
    return c;
}

// Compact 5x7 glyphs used by the result panel. Each hexadecimal nibble is a
// row; the font occupies four columns plus one blank column.
static uint32_t result_glyph(char c) {
    switch (c) {
    case '0': return 0x6999996; case '1': return 0x2622227;
    case '2': return 0x691248f; case '3': return 0xe112196;
    case '4': return 0x99f1111; case '5': return 0xf8e1196;
    case '6': return 0x688e996; case '7': return 0xf112444;
    case '8': return 0x6996996; case '9': return 0x6997116;
    case 'T': return 0xf222222; case 'I': return 0x7222227;
    case 'P': return 0xe99e888; case 'S': return 0x788611e;
    case ':': return 0x0200200; case '-': return 0x000f000;
    default: return 0;
    }
}

static void draw_result_char(ap_uint<32> *work, int x, int y, char c) {
    uint32_t glyph = result_glyph(c);
    for (int row=0; row<7; ++row) for (int col=0; col<4; ++col) {
        bool pixel = (glyph >> ((6-row)*4 + (3-col))) & 1;
        if (pixel) for (int dy=0; dy<2; ++dy) for (int dx=0; dx<2; ++dx)
            panel_write(work, 5, x+col*2+dx, y+row*2+dy, RGB{255,255,255});
    }
}

static inline RGB bilinear_panel(const ap_uint<32> *work, int panel,
                                 int x, int y, int out_w) {
#pragma HLS INLINE
    // Output scaling only affects the enlarged display tiles; one DDR read
    // per output pixel avoids four-way traffic on the single panel workspace.
    int sx=(out_w==426)?(x*320)/426:(x*320)/427;
    int sy=(y*240)/320;
    return panel_read(work,panel,sx,sy);
}

static void resize_2x_panel(ap_uint<32> *work, int panel, const ap_uint<32> *src) {
    for (int y = 0; y < PANEL_H; ++y) {
        for (int x = 0; x < PANEL_W; ++x) {
#pragma HLS PIPELINE II=1
            // Half-pixel bilinear enlargement used by the Python panel path.
            // Equivalent to floor((2*x-1)/4) and floor((2*y-1)/4),
            // expressed directly from output-coordinate parity.
            int x0=(x>>1)-((x&1)==0), y0=(y>>1)-((y&1)==0);
            RGB a=get_rgb(src,x0,y0), b=get_rgb(src,x0+1,y0);
            RGB c=get_rgb(src,x0,y0+1), d=get_rgb(src,x0+1,y0+1), o;
            // For a 2x resize, the half-pixel fractional weights alternate
            // exactly between 1/4 and 3/4. Apply the bilinear weights as
            // shift-adds (3*v = 2*v + v), preserving the rounded /16 result
            // while avoiding a long multi-DSP multiply/accumulate cascade.
            bool fx_one=(x&1), fy_one=(y&1);
            uint16_t ar=fx_one?((a.r<<1)+a.r+b.r):(a.r+(b.r<<1)+b.r);
            uint16_t ag=fx_one?((a.g<<1)+a.g+b.g):(a.g+(b.g<<1)+b.g);
            uint16_t ab=fx_one?((a.b<<1)+a.b+b.b):(a.b+(b.b<<1)+b.b);
            uint16_t cr=fx_one?((c.r<<1)+c.r+d.r):(c.r+(d.r<<1)+d.r);
            uint16_t cg=fx_one?((c.g<<1)+c.g+d.g):(c.g+(d.g<<1)+d.g);
            uint16_t cb=fx_one?((c.b<<1)+c.b+d.b):(c.b+(d.b<<1)+d.b);
            o.r=(uint8_t)((((fy_one?((ar<<1)+ar+cr):(ar+(cr<<1)+cr))+8)>>4));
            o.g=(uint8_t)((((fy_one?((ag<<1)+ag+cg):(ag+(cg<<1)+cg))+8)>>4));
            o.b=(uint8_t)((((fy_one?((ab<<1)+ab+cb):(ab+(cb<<1)+cb))+8)>>4));
            panel_write(work, panel, x, y, o);
        }
    }
}

static void raw_camera_panel(const ap_uint<16> *camera_frame,
                             ap_uint<32> *panel_workspace) {
    // Panel 1 is the original camera view, reduced directly from 640x480 to
    // 320x240 with a 2x2 box average. This preserves the complete 4:3 field.
    for (int y = 0; y < PANEL_H; ++y) {
        for (int x = 0; x < PANEL_W; ++x) {
#pragma HLS PIPELINE II=1
            int sx = 2 * x, sy = 2 * y;
            RGB a = rgb565_to_rgb(camera_frame[sy * IN_W + sx]);
            RGB b = rgb565_to_rgb(camera_frame[sy * IN_W + sx + 1]);
            RGB c = rgb565_to_rgb(camera_frame[(sy + 1) * IN_W + sx]);
            RGB d = rgb565_to_rgb(camera_frame[(sy + 1) * IN_W + sx + 1]);
            RGB q = {
                (uint8_t)((a.r + b.r + c.r + d.r + 2) >> 2),
                (uint8_t)((a.g + b.g + c.g + d.g + 2) >> 2),
                (uint8_t)((a.b + b.b + c.b + d.b + 2) >> 2)
            };
            panel_write(panel_workspace, 0, x, y, q);
        }
    }
}

static void gaussian_fill_light(const ap_uint<16> *camera_frame, ap_uint<32> *dst, uint8_t *gray,
                                uint8_t *illum_h, uint8_t *illum_v) {
    // Python: GaussianBlur(V, sigmaX=8), reference=median(illumination),
    // gain=clip(reference/max(illumination,24),0.60,2.20). Q12 separable taps.
    static const uint16_t k[49] = {
        2,3,5,7,9,12,16,21,28,35,44,55,66,80,94,109,124,140,155,168,
        181,191,198,203,205,203,198,191,181,168,155,140,124,109,94,80,
        66,55,44,35,28,21,16,12,9,7,5,3,2
    };
    uint16_t hist[256];
    for (int i=0;i<256;i++) hist[i]=0;
    for (int i=0;i<N;i++) {
        HSV h = rgb_to_hsv(sampled_rgb(camera_frame,i%W,i/W)); gray[i] = h.v;
    }
    for (int y=0;y<H;y++) for (int x=0;x<W;x++) {
        uint32_t v=0;
        for (int j=0;j<49;j++) {
#pragma HLS PIPELINE II=1
            v += k[j] * get_u8(gray,x+j-24,y);
        }
        illum_h[y*W+x]=(uint8_t)((v+2048)>>12);
    }
    for (int y=0;y<H;y++) for (int x=0;x<W;x++) {
        uint32_t v=0;
        for (int j=0;j<49;j++) {
#pragma HLS PIPELINE II=1
            v += k[j] * illum_h[reflect101(y+j-24,H)*W+x];
        }
        uint8_t q=(uint8_t)((v+2048)>>12);
        illum_v[y*W+x]=q;
        hist[q]++;
    }
    uint32_t acc=0; uint8_t reference=0;
    for(int b=0;b<256;b++){acc+=hist[b];if(acc>=N/2){reference=(uint8_t)b;break;}}
    for(int i=0;i<N;i++){
        HSV h=rgb_to_hsv(sampled_rgb(camera_frame,i%W,i/W)); uint8_t denom=illum_v[i]<24?24:illum_v[i];
        uint32_t gain=div_u16_u8((uint16_t)((uint32_t)reference<<8),denom);
        if(gain<154)gain=154;if(gain>563)gain=563;
        h.v=clip8((int)(((uint32_t)h.v*gain+128)>>8)); dst[i]=pack_rgb(hsv_to_rgb(h));
    }
}

static void make_canny(const ap_uint<16> *camera_frame, ap_uint<2> *edges, uint8_t *gray,
                       uint8_t *blur, int16_t *gx, int16_t *gy,
                       uint16_t *mag) {
    for(int i=0;i<N;i++){
        RGB p=sampled_rgb(camera_frame,i%W,i/W);
        gray[i]=(uint8_t)((77*p.r+150*p.g+29*p.b+128)>>8);
    }
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){

        int v=get_u8(gray,x-1,y-1)+2*get_u8(gray,x,y-1)+get_u8(gray,x+1,y-1)
             +2*get_u8(gray,x-1,y)+4*get_u8(gray,x,y)+2*get_u8(gray,x+1,y)
             +get_u8(gray,x-1,y+1)+2*get_u8(gray,x,y+1)+get_u8(gray,x+1,y+1);
        blur[y*W+x]=(uint8_t)((v+8)>>4);
    }
    for(int y=1;y<H-1;y++)for(int x=1;x<W-1;x++){

        int i=y*W+x;
        int a=blur[i-W-1],b=blur[i-W],c=blur[i-W+1],d=blur[i-1],f=blur[i+1],g=blur[i+W-1],h=blur[i+W],j=blur[i+W+1];
        gx[i]=(int16_t)(-a+c-2*d+2*f-g+j); gy[i]=(int16_t)(-a-2*b-c+g+2*h+j);
        mag[i]=(uint16_t)(hls::abs((int)gx[i])+hls::abs((int)gy[i]));
    }
    for(int i=0;i<N;i++)edges[i]=0;
    for(int y=1;y<H-1;y++)for(int x=1;x<W-1;x++){

        int i=y*W+x, ax=hls::abs((int)gx[i]), ay=hls::abs((int)gy[i]);
        int p1,p2;
        if(ay*2<ax){p1=i-1;p2=i+1;}
        else if(ax*2<ay){p1=i-W;p2=i+W;}
        else if((gx[i]^gy[i])>=0){p1=i-W-1;p2=i+W+1;}
        else {p1=i-W+1;p2=i+W-1;}
        if(mag[i]>=mag[p1]&&mag[i]>=mag[p2]) edges[i]=(mag[i]>=32)?2:((mag[i]>=14)?1:0);
    }
    // Hysteresis propagation along 8-connected weak edges.
    for(int pass=0;pass<8;pass++){
        for(int y=1;y<H-1;y++)for(int x=1;x<W-1;x++){

            int i=y*W+x;
            if(edges[i]==1 && (edges[i-1]==2||edges[i+1]==2||edges[i-W]==2||edges[i+W]==2||edges[i-W-1]==2||edges[i-W+1]==2||edges[i+W-1]==2||edges[i+W+1]==2)) edges[i]=2;
        }
    }
    for(int i=0;i<N;i++)edges[i]=(edges[i]==2);
}

static void morphology(const ap_uint<1> *in, ap_uint<1> *out, int size, int dilate) {
    int r=size/2;
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){

        ap_uint<1> val=dilate?0:1;
        for(int dy=-r;dy<=r;dy++)for(int dx=-r;dx<=r;dx++){
            int xx=x+dx,yy=y+dy;
            if((dx*dx+dy*dy)<=r*r+1){
                ap_uint<1> q=(xx<0||xx>=W||yy<0||yy>=H)?ap_uint<1>(0):in[yy*W+xx];
                if(dilate){if(q)val=1;}else{if(!q)val=0;}
            }
        }
        out[y*W+x]=val;
    }
}

static bool largest_component(ap_uint<1> *mask, uint16_t *labels,
                               uint32_t *component_area, uint16_t *component_xmin,
                               uint16_t *component_ymin, uint16_t *component_xmax,
                               uint16_t *component_ymax, uint16_t *queue_mem) {
    uint16_t next_label=0;
    for(int i=0;i<N;i++){labels[i]=0;}
    for(int i=0;i<=N;i++){component_area[i]=0;component_xmin[i]=W;component_ymin[i]=H;component_xmax[i]=0;component_ymax[i]=0;}
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
        int seed=y*W+x;if(!mask[seed]||labels[seed])continue;
        ++next_label;int head=0,tail=0;queue_mem[tail++]=seed;labels[seed]=next_label;
        while(head<tail){
            int p=queue_mem[head++],px=p%W,py=p/W;
            component_area[next_label]++;
            if(px<component_xmin[next_label])component_xmin[next_label]=px;
            if(px>component_xmax[next_label])component_xmax[next_label]=px;
            if(py<component_ymin[next_label])component_ymin[next_label]=py;
            if(py>component_ymax[next_label])component_ymax[next_label]=py;
            for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
                int xx=px+dx,yy=py+dy;if(xx<0||xx>=W||yy<0||yy>=H)continue;
                int q=yy*W+xx;if(mask[q]&&!labels[q]){labels[q]=next_label;queue_mem[tail++]=q;}
            }
        }
    }
    uint16_t best=0;uint32_t best_area=0;
    for(int l=1;l<=next_label;l++)if(component_area[l]>best_area){best_area=component_area[l];best=l;}
    if(best_area<31){for(int i=0;i<N;i++)mask[i]=0;return false;}
    for(int i=0;i<N;i++)mask[i]=(labels[i]==best);
    return true;
}

// Flood the exterior background with 4-connectivity; remaining background
// pixels are enclosed holes and become foreground. Queue capacity is N.
static void fill_enclosed_holes(ap_uint<1> *mask, ap_uint<1> *visited, uint16_t *queue_mem) {
    for(int i=0;i<N;i++) visited[i]=0;
    int head=0,tail=0;
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
        int i=y*W+x;
        if((x==0||x==W-1||y==0||y==H-1)&&!mask[i]&&!visited[i]){
            visited[i]=1;queue_mem[tail++]=i;
        }
    }
    while(head<tail){
        int p=queue_mem[head++], x=p%W, y=p/W;
        for(int d=0;d<4;d++){
            int xx=x+(d==0)-(d==1), yy=y+(d==2)-(d==3);
            if(xx<0||xx>=W||yy<0||yy>=H)continue;
            int q=yy*W+xx;
            if(!mask[q]&&!visited[q]){visited[q]=1;queue_mem[tail++]=q;}
        }
    }
    for(int i=0;i<N;i++){
        bool hole=!mask[i]&&!visited[i];
        if(hole)mask[i]=1;
        visited[i]=hole;
    }
}

static void make_shadow_mask(const ap_uint<32> *src, ap_uint<32> *denoised,
                             ap_uint<1> *mask_a, ap_uint<1> *mask_b, uint16_t *labels,
                             uint32_t *component_area, uint16_t *component_xmin,
                             uint16_t *component_ymin, uint16_t *component_xmax,
                             uint16_t *component_ymax, uint16_t *queue_mem) {
    // Hardware-oriented bilateral filter (5x5, sigmaColor=28, sigmaSpace=4),
    // followed by the Python row-wise hue-baseline/median threshold.
    static const uint16_t spatial[25] = {3190,3503,3615,3503,3190,3503,3848,3970,3848,3503,3615,3970,4096,3970,3615,3503,3848,3970,3848,3503,3190,3503,3615,3503,3190};
    static const uint16_t range_weight[256] = {4096,3479,2955,2510,2132,1811,1538,1306,1109,942,800,680,577,490,417,354,301,255,217,184,156,133,113,96,81,69,59,50,42,36,31,26,22,19,16,14,11,10,8,7,6,5,4,4,3,3,2,2,2,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
        RGB center=get_rgb(src,x,y);uint32_t sr=0,sg=0,sb=0,sw=0;int k=0;
        for(int dy=-2;dy<=2;dy++)for(int dx=-2;dx<=2;dx++){
#pragma HLS PIPELINE II=1
            RGB q=get_rgb(src,x+dx,y+dy);int dr=(int)q.r-center.r,dg=(int)q.g-center.g,db=(int)q.b-center.b;
            uint32_t dist=(uint32_t)(dr*dr+dg*dg+db*db);uint32_t ri=dist>>8;if(ri>255)ri=255;
            uint32_t w=((uint32_t)spatial[k++]*range_weight[ri]+2048)>>12;
            sr+=w*q.r;sg+=w*q.g;sb+=w*q.b;sw+=w;
        }
        denoised[y*W+x]=pack_rgb(RGB{(uint8_t)(sr/sw), (uint8_t)(sg/sw), (uint8_t)(sb/sw)});
    }
    uint8_t baseline[H];
    for(int y=0;y<H;y++){
        uint8_t samples[40];for(int i=0;i<40;i++){
            int x=(i<20)?i:W-20+(i-20);samples[i]=rgb_to_hsv(unpack_rgb(denoised[y*W+x])).h;
        }
        for(int i=1;i<40;i++){uint8_t v=samples[i];int j=i-1;while(j>=0&&samples[j]>v){samples[j+1]=samples[j];--j;}samples[j+1]=v;}
        baseline[y]=(samples[19]+samples[20])/2;
    }
    uint8_t med[H];
    for(int y=0;y<H;y++){
        uint8_t a[11];for(int k=-5;k<=5;k++){int yy=reflect101(y+k,H);a[k+5]=baseline[yy];}
        for(int i=1;i<11;i++){uint8_t v=a[i];int j=i-1;while(j>=0&&a[j]>v){a[j+1]=a[j];--j;}a[j+1]=v;}
        med[y]=a[5];
    }
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){

        HSV h=rgb_to_hsv(unpack_rgb(denoised[y*W+x]));int d=h.h>med[y]?h.h-med[y]:med[y]-h.h;if(d>90)d=180-d;
        mask_b[y*W+x]=(d>=12&&h.s>=40&&x>=5&&x<W-5&&y>=5&&y<H-5);
    }
    morphology(mask_b,mask_a,3,0);morphology(mask_a,mask_b,3,1);
    morphology(mask_b,mask_a,5,1);morphology(mask_a,mask_b,5,0);
    for(int i=0;i<N;i++)mask_a[i]=mask_b[i];
    (void)largest_component(mask_a,labels,component_area,component_xmin,
                            component_ymin,component_xmax,component_ymax,queue_mem);
}

// Dark-object candidate. The edge median adapts to ambient light; implausible
// or clipped candidates fall back to the Python-derived hue mask.
static bool detector_dark_mask(const uint8_t *gray, ap_uint<1> *candidate,
        uint16_t *labels, uint32_t *areas, uint16_t *xmin, uint16_t *ymin,
        uint16_t *xmax, uint16_t *ymax, uint16_t *queue_mem) {
    uint16_t hist[256];
    for(int i=0;i<256;i++) hist[i]=0;
    int samples=0;
    for(int y=0;y<H;y++) for(int x=0;x<W;x++) {
        if(x<10||x>=W-10||y<10||y>=H-10){hist[gray[y*W+x]]++;samples++;}
    }
    int accumulated=0, background=0;
    for(int i=0;i<256;i++){accumulated+=hist[i];if(accumulated>=(samples+1)/2){background=i;break;}}
    if(background<48)return false;
    int threshold=(background*62)/100;
    for(int y=0;y<H;y++) for(int x=0;x<W;x++)
        candidate[y*W+x]=(x>=5 && x<W-5 && y>=5 && y<H-5 && gray[y*W+x]<=threshold);
    if(!largest_component(candidate,labels,areas,xmin,ymin,xmax,ymax,queue_mem))return false;
    int area=0, lx=W, ly=H, rx=-1, ry=-1;
    for(int y=0;y<H;y++)for(int x=0;x<W;x++)if(candidate[y*W+x]){
        area++;if(x<lx)lx=x;if(x>rx)rx=x;if(y<ly)ly=y;if(y>ry)ry=y;
    }
    return area>=100 && area<N/3 && rx-lx>=12 && ry-ly>=12 && lx>5 && ly>5 && rx<W-6 && ry<H-6;
}

static int radial_peaks(const ap_uint<1> *mask, ap_uint<1> *eroded,
                        Point &center, Point *points) {
    static const uint8_t atan_deg[257] = {0,0,0,0,0,1,1,1,1,2,2,2,2,2,3,3,3,3,4,4,4,4,4,5,5,5,5,6,6,6,6,6,7,7,7,7,8,8,8,8,8,9,9,9,9,9,10,10,10,10,11,11,11,11,11,12,12,12,12,12,13,13,13,13,14,14,14,14,14,15,15,15,15,15,16,16,16,16,16,17,17,17,17,17,18,18,18,18,18,19,19,19,19,19,20,20,20,20,20,21,21,21,21,21,22,22,22,22,22,23,23,23,23,23,24,24,24,24,24,24,25,25,25,25,25,26,26,26,26,26,26,27,27,27,27,27,27,28,28,28,28,28,29,29,29,29,29,29,30,30,30,30,30,30,31,31,31,31,31,31,32,32,32,32,32,32,32,33,33,33,33,33,33,34,34,34,34,34,34,34,35,35,35,35,35,35,36,36,36,36,36,36,36,37,37,37,37,37,37,37,37,38,38,38,38,38,38,38,39,39,39,39,39,39,39,40,40,40,40,40,40,40,40,41,41,41,41,41,41,41,41,42,42,42,42,42,42,42,42,43,43,43,43,43,43,43,43,43,44,44,44,44,44,44,44,44,45};
    // Gaussian weights in Q12. Their sum is 4096, keeping the smoothed
    // radius in the same Q8 pixel units as the raw boundary coordinates.
    static const uint16_t smooth_w[13] = {76,140,231,340,449,531,562,531,449,340,231,140,76};
    int count=0;uint32_t sx=0,sy=0;
    for(int y=0;y<H;y++)for(int x=0;x<W;x++)if(mask[y*W+x]){sx+=x;sy+=y;++count;}
    if(count<10){center={0,0};return 0;}
    center={(int32_t)((sx<<8)/count),(int32_t)((sy<<8)/count)};
    morphology(mask,eroded,3,0);
    for(int b=0;b<360;b++){radial[b]=-1;radial_x[b]=radial_y[b]=0;radial_valid[b]=0;}
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
        int i=y*W+x;if(!mask[i]||eroded[i])continue;
        int32_t dx=(x<<8)-center.x,dy=center.y-(y<<8);
        uint32_t ax=hls::abs((int)dx),ay=hls::abs((int)dy),hi=ax>ay?ax:ay,lo=ax>ay?ay:ax;
        if(!hi)continue;
        uint32_t ri=(lo<<8)/hi;if(ri>256)ri=256;
        int a=atan_deg[ri],bin;
        if(ay>ax)a=90-a;
        if(dx>=0&&dy>=0)bin=a;
        else if(dx<0&&dy>=0)bin=180-a;
        else if(dx<0&&dy<0)bin=180+a;
        else {bin=360-a;if(bin==360)bin=0;}
        int32_t radius=(int32_t)(hi+((lo*106)>>8));
        if(radius>radial[bin]){radial[bin]=radius;radial_x[bin]=(uint16_t)(x<<8);radial_y[bin]=(uint16_t)(y<<8);radial_valid[bin]=1;}
    }
    int valid=0;for(int b=0;b<360;b++)if(radial[b]>=0)++valid;
    if(valid<180){for(int b=0;b<360;b++)radial[b]=0;return 0;}
    for(int b=0;b<360;b++)if(radial[b]<0){
        int l=1,r=1;while(l<360&&!radial_valid[(b-l+360)%360])++l;while(r<360&&!radial_valid[(b+r)%360])++r;
        int32_t lv=radial[(b-l+360)%360],rv=radial[(b+r)%360];
        radial[b]=lv+(int32_t)(((int64_t)(rv-lv)*l)/(l+r));
        int nearest=(l<=r)?(b-l+360)%360:(b+r)%360;
        radial_x[b]=radial_x[nearest];radial_y[b]=radial_y[nearest];
    }
    for(int b=0;b<360;b++){
        int64_t v=0;for(int i=-6;i<=6;i++)v+=(int64_t)smooth_w[i+6]*radial[(b+i+360)%360];
        smooth_radial[b]=(int32_t)((v+2048)>>12);
    }
    int32_t sorted[360];for(int i=0;i<360;i++)sorted[i]=smooth_radial[i];
    for(int i=1;i<360;i++){int32_t v=sorted[i];int j=i-1;while(j>=0&&sorted[j]>v){sorted[j+1]=sorted[j];--j;}sorted[j+1]=v;}
    int32_t prominence_min=(sorted[342]-sorted[36])*5/1000;if(prominence_min<90)prominence_min=90;
    current_scale=sorted[342]>256?sorted[342]:256;
    int candidates=0;const int radius=9;
    for(int b=0;b<360;b++){
        bool peak=smooth_radial[b]>smooth_radial[(b+359)%360];
        int32_t localmin1=smooth_radial[b],localmin2=smooth_radial[b];
        for(int d=1;d<=radius;d++){
            int l=(b-d+360)%360,r=(b+d)%360;
            if(smooth_radial[l]>smooth_radial[b]||smooth_radial[r]>smooth_radial[b])peak=false;
            if(smooth_radial[l]<localmin1)localmin1=smooth_radial[l];
            if(smooth_radial[r]<localmin2)localmin2=smooth_radial[r];
        }
        int32_t floor=localmin1>localmin2?localmin1:localmin2;
        int32_t prom=smooth_radial[b]-floor;
        if(peak&&prom>=prominence_min&&candidates<360){peak_bins[candidates]=b;peak_prom[candidates]=prom;++candidates;}
    }
    bool selected[360];for(int i=0;i<candidates;i++)selected[i]=false;
    int chosen[360],nchosen=0;
    for(int iter=0;iter<candidates;iter++){
        int best=-1;for(int i=0;i<candidates;i++)if(!selected[i]&&(best<0||smooth_radial[peak_bins[i]]>smooth_radial[peak_bins[best]]||(smooth_radial[peak_bins[i]]==smooth_radial[peak_bins[best]]&&peak_prom[i]>peak_prom[best])))best=i;
        if(best<0)break;selected[best]=true;bool far=true;
        for(int j=0;j<nchosen;j++){int d=hls::abs((int)peak_bins[best]-(int)peak_bins[chosen[j]]);if(d>180)d=360-d;if(d<18)far=false;}
        if(far&&nchosen<MAX_TIPS)chosen[nchosen++]=best;
    }
    for(int i=0;i<nchosen;i++){int b=peak_bins[chosen[i]];points[i]={(int32_t)radial_x[b],(int32_t)radial_y[b]};}
    return nchosen;
}

extern "C" void sixpanel_accel(const ap_uint<16> *camera_frame,
                               ap_uint<16> *mosaic_frame,
                               ap_uint<32> *fill_history,
                               ap_uint<32> *panel_workspace,
                               ap_uint<8> &stable_tip_count,
                               ap_uint<1> &detector_valid,
                               ap_uint<1> &frame_done,
                               ap_uint<1> clear_history) {
#pragma HLS INTERFACE m_axi port=camera_frame offset=slave bundle=gmem_cam depth=307200 max_read_burst_length=64
#pragma HLS INTERFACE m_axi port=mosaic_frame offset=slave bundle=gmem_out depth=819200 max_write_burst_length=64
#pragma HLS INTERFACE m_axi port=fill_history offset=slave bundle=gmem_hist depth=96000
#pragma HLS INTERFACE m_axi port=panel_workspace offset=slave bundle=gmem_work depth=900000
#pragma HLS INTERFACE s_axilite port=camera_frame bundle=control
#pragma HLS INTERFACE s_axilite port=mosaic_frame bundle=control
#pragma HLS INTERFACE s_axilite port=fill_history bundle=control
#pragma HLS INTERFACE s_axilite port=panel_workspace bundle=control
#pragma HLS INTERFACE ap_none port=stable_tip_count
#pragma HLS INTERFACE ap_none port=detector_valid
#pragma HLS INTERFACE ap_none port=frame_done
#pragma HLS INTERFACE s_axilite port=clear_history bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

    frame_done = 0;
    const int base = 6 * PANEL_N;
    // Reserve three full-frame DDR buffers after the six panel tiles. Each
    // RGB word uses the low 24 bits of one 32-bit workspace word.
    ap_uint<32> *stable = &panel_workspace[base + 0 * SCRATCH_WORDS];
    ap_uint<32> *denoised = &panel_workspace[base + 1 * SCRATCH_WORDS];
    ap_uint<32> *corrected = corrected_buf;
    uint8_t *gray=gray_buf, *blur=blur_buf;
    ap_uint<1> *mask_a=mask_a_buf, *mask_b=mask_b_buf;
    ap_uint<2> *edge_map=edge_buf;
    int16_t *gx=gx_buf, *gy=gy_buf;
    uint16_t *mag=mag_buf;
    uint16_t *labels = reinterpret_cast<uint16_t *>(&panel_workspace[base + 12*SCRATCH_WORDS]);
    uint16_t *queue_mem = reinterpret_cast<uint16_t *>(&panel_workspace[base + 13*SCRATCH_WORDS]);
    uint32_t *component_area = reinterpret_cast<uint32_t *>(&panel_workspace[base + 14*SCRATCH_WORDS]);
    uint16_t *component_xmin = reinterpret_cast<uint16_t *>(&panel_workspace[base + 15*SCRATCH_WORDS]);
    uint16_t *component_ymin = reinterpret_cast<uint16_t *>(&panel_workspace[base + 16*SCRATCH_WORDS]);
    uint16_t *component_xmax = reinterpret_cast<uint16_t *>(&panel_workspace[base + 17*SCRATCH_WORDS]);
    uint16_t *component_ymax = reinterpret_cast<uint16_t *>(&panel_workspace[base + 18*SCRATCH_WORDS]);
    uint8_t *illum_h=blur_buf; // reused by Canny after the illumination pass
    uint8_t *illum_v=gray_buf; // gray is dead after the horizontal blur

    if(clear_history){fill_history_count=0;fill_frame_index=0;tip_history_count=0;tip_history_write=0;detector_source_initialized=false;}

    // Sample the camera frame directly from DDR. This removes a full RGB frame
    // store in BRAM while retaining the [::2, ::2] plus INTER_AREA sample.
    gaussian_fill_light(camera_frame, corrected, gray, blur, gray);
    uint8_t slot=fill_history_count<HIST?fill_history_count:(fill_frame_index%HIST);
    for(int i=0;i<N;i++){

        uint32_t q=corrected[i];
        fill_history[slot*N+i]=q;
        uint8_t rr[5],gg[5],bb[5];int count=fill_history_count<HIST?fill_history_count+1:HIST;
        for(int h=0;h<HIST;h++){
            int hs=(slot-h+HIST)%HIST;uint32_t p=(h<count)?(uint32_t)fill_history[hs*N+i]:q;
            rr[h]=(p>>16)&255;gg[h]=(p>>8)&255;bb[h]=p&255;
        }
        // Sort only the valid temporal samples independently per channel.
        for(int a=1;a<count;a++){uint8_t v=rr[a];int b=a-1;while(b>=0&&rr[b]>v){rr[b+1]=rr[b];--b;}rr[b+1]=v;}
        for(int a=1;a<count;a++){uint8_t v=gg[a];int b=a-1;while(b>=0&&gg[b]>v){gg[b+1]=gg[b];--b;}gg[b+1]=v;}
        for(int a=1;a<count;a++){uint8_t v=bb[a];int b=a-1;while(b>=0&&bb[b]>v){bb[b+1]=bb[b];--b;}bb[b+1]=v;}
        stable[i]=pack_rgb(RGB{ (uint8_t)((count&1)?rr[count/2]:((rr[count/2-1]+rr[count/2])/2)),
                                (uint8_t)((count&1)?gg[count/2]:((gg[count/2-1]+gg[count/2])/2)),
                                (uint8_t)((count&1)?bb[count/2]:((bb[count/2-1]+bb[count/2])/2)) });
    }
    if(fill_history_count<HIST)fill_history_count++;else fill_frame_index++;

    // Panel 1: original full-frame camera image.
    raw_camera_panel(camera_frame,panel_workspace);

    // Panel 3 displays the Python illumination correction. Pure chroma
    // normalization forces the brightest channel to 255 and is useful for
    // segmentation, but washes out this view of a dark specimen.
    resize_2x_panel(panel_workspace,2,stable);

    // Segment using illumination-corrected brightness, so a cast shadow is
    // less likely to merge into the target outline.
    for(int i=0;i<N;i++){
        RGB p=unpack_rgb(stable[i]);
        gray[i]=(uint8_t)((77*p.r+150*p.g+29*p.b+128)>>8);
    }
    bool dark_mask=detector_dark_mask(gray,mask_b,labels,component_area,component_xmin,component_ymin,
                                      component_xmax,component_ymax,queue_mem);
    if(detector_source_initialized && dark_mask!=previous_dark_detector){tip_history_count=0;tip_history_write=0;}
    detector_source_initialized=true;previous_dark_detector=dark_mask;
    if(dark_mask){for(int i=0;i<N;i++)mask_a[i]=mask_b[i];}
    else {
        for(int i=0;i<N;i++){
            RGB p=unpack_rgb(stable[i]);
            uint8_t mx=p.r>p.g?(p.r>p.b?p.r:p.b):(p.g>p.b?p.g:p.b);
            corrected[i]=pack_rgb(mx?RGB{(uint8_t)div_u16_u8((uint16_t)p.r*255,mx),(uint8_t)div_u16_u8((uint16_t)p.g*255,mx),(uint8_t)div_u16_u8((uint16_t)p.b*255,mx)}:RGB{0,0,0});
        }
        make_shadow_mask(corrected,denoised,mask_a,mask_b,labels,
                         component_area,component_xmin,component_ymin,
                         component_xmax,component_ymax,queue_mem);
    }
    fill_enclosed_holes(mask_a,mask_b,queue_mem);
    // Panel 2: the silhouette boundary of the exact filled mask used by panel 4.
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){
        int i=y*W+x;
        bool edge=mask_a[i] && (x==0||y==0||x==W-1||y==H-1||
                    !mask_a[i-1]||!mask_a[i+1]||!mask_a[i-W]||!mask_a[i+W]);
        corrected[i]=pack_rgb(edge?RGB{40,220,255}:RGB{28,28,28});
    }
    resize_2x_panel(panel_workspace,1,corrected);
    int xmin=W,ymin=H,xmax=-1,ymax=-1;
    for(int y=0;y<H;y++)for(int x=0;x<W;x++)if(mask_a[y*W+x]){
        if(x<xmin)xmin=x;if(x>xmax)xmax=x;if(y<ymin)ymin=y;if(y>ymax)ymax=y;
    }
    // Panel 4: full-field white-background segmentation. Keep the original
    // camera coordinates instead of cropping to the detected bounding box.
    for(int y=0;y<PANEL_H;y++)for(int x=0;x<PANEL_W;x++){
        int sx=x/2,sy=y/2;
        RGB q=mask_a[sy*W+sx]?(mask_b[sy*W+sx]?RGB{0,0,0}:panel_read(panel_workspace,0,x,y)):RGB{255,255,255};
        panel_write(panel_workspace,3,x,y,q);
    }
    // Panel 5 uses the same uncropped coordinate system before drawing radial
    // candidates, so every marker stays aligned with the complete specimen.
    for(int y=0;y<PANEL_H;y++)for(int x=0;x<PANEL_W;x++){

        panel_write(panel_workspace,4,x,y,panel_read(panel_workspace,0,x,y));
    }
    Point center;int candidates=radial_peaks(mask_a,mask_b,center,current_tips);
    // Keep radial candidates in a nine-frame circular history and accept a
    // point only when the same normalized location recurs in >=55% of frames.
    history_tip_counts[tip_history_write]=candidates;
    history_tip_valid[tip_history_write]=(candidates>0);
    for(int i=0;i<MAX_TIPS;i++){
        if(i<candidates)history_tips[tip_history_write][i]={
            (int32_t)(((int64_t)(current_tips[i].x-center.x)<<8)/current_scale),
            (int32_t)(((int64_t)(current_tips[i].y-center.y)<<8)/current_scale)};
        else history_tips[tip_history_write][i]=Point{0,0};
    }
    tip_history_write=(tip_history_write+1)%TIP_HIST;if(tip_history_count<TIP_HIST)tip_history_count++;
    int required=(int)((tip_history_count*55+99)/100);if(required<2)required=2;
    Point stable_points[MAX_TIPS];int stable_count=0;
    for(int i=0;i<candidates&&stable_count<MAX_TIPS;i++){
        int hits=0;for(int h=0;h<tip_history_count;h++){
            int idx=(tip_history_write-1-h+TIP_HIST)%TIP_HIST;bool found=false;
            Point now={(int32_t)(((int64_t)(current_tips[i].x-center.x)<<8)/current_scale),
                       (int32_t)(((int64_t)(current_tips[i].y-center.y)<<8)/current_scale)};
            for(int j=0;j<history_tip_counts[idx];j++){
                int32_t dx=now.x-history_tips[idx][j].x,dy=now.y-history_tips[idx][j].y;
                if(dx*dx+dy*dy<=46*46){found=true;break;}
            }
            if(found)hits++;
        }
        if(hits>=required)stable_points[stable_count++]=current_tips[i];
    }
    stable_tip_count=(uint8_t)stable_count;
    detector_valid=(xmin<=xmax && stable_count>0);

    // Overlay the contour on the full camera view. The detector still uses the
    // original mask; these display annotations do not affect classification.
    for(int y=0;y<PANEL_H;y++)for(int x=0;x<PANEL_W;x++){
        int sx=x/2,sy=y/2,idx=sy*W+sx;
        bool inside=mask_a[idx];
        bool boundary=inside && (sx==0 || sy==0 || sx==W-1 || sy==H-1 ||
            !mask_a[idx-1] || !mask_a[idx+1] || !mask_a[idx-W] || !mask_a[idx+W]);
        RGB q=panel_read(panel_workspace,0,x,y);
        if(boundary) q=RGB{0,255,255};
        panel_write(panel_workspace,5,x,y,q);
    }
    // Draw candidate markers/center in panel 5 (angles) and stable markers in
    // panel 6 (consensus). Annotations never feed back into the detector.
    for(int i=0;i<candidates;i++){
        int px=(current_tips[i].x*2+128)>>8,py=(current_tips[i].y*2+128)>>8;
        int cx=(center.x*2+128)>>8,cy=(center.y*2+128)>>8;
        int steps=hls::abs(px-cx)>hls::abs(py-cy)?hls::abs(px-cx):hls::abs(py-cy);if(steps<1)steps=1;
        for(int j=0;j<=steps;j++)panel_write(panel_workspace,4,cx+(px-cx)*j/steps,cy+(py-cy)*j/steps,RGB{35,190,35});
        for(int dy=-4;dy<=4;dy++)for(int dx=-4;dx<=4;dx++)if(dx*dx+dy*dy<=16){panel_write(panel_workspace,4,px+dx,py+dy,RGB{225,20,20});}
    }
    for(int dy=-4;dy<=4;dy++)for(int dx=-4;dx<=4;dx++)if(dx*dx+dy*dy<=16){panel_write(panel_workspace,4,((center.x*2+128)>>8)+dx,((center.y*2+128)>>8)+dy,RGB{20,80,220});}
    for(int i=0;i<stable_count;i++){
        int px=(stable_points[i].x*2+128)>>8,py=(stable_points[i].y*2+128)>>8;
        int cx=(center.x*2+128)>>8,cy=(center.y*2+128)>>8;
        int steps=hls::abs(px-cx)>hls::abs(py-cy)?hls::abs(px-cx):hls::abs(py-cy);if(steps<1)steps=1;
        for(int j=0;j<=steps;j++)panel_write(panel_workspace,5,cx+(px-cx)*j/steps,cy+(py-cy)*j/steps,RGB{40,180,40});
        for(int dy=-4;dy<=4;dy++)for(int dx=-4;dx<=4;dx++)if(dx*dx+dy*dy<=16){panel_write(panel_workspace,5,px+dx,py+dy,RGB{225,20,20});}
    }
    // Bottom legend is outside the mosaic's 27-pixel top header.
    for(int y=218;y<238;y++)for(int x=4;x<104;x++)panel_write(panel_workspace,5,x,y,RGB{20,20,20});
    draw_result_char(panel_workspace,8,221,'T');
    draw_result_char(panel_workspace,18,221,'I');
    draw_result_char(panel_workspace,28,221,'P');
    draw_result_char(panel_workspace,38,221,'S');
    draw_result_char(panel_workspace,48,221,':');
    if(detector_valid){
        draw_result_char(panel_workspace,62,221,'0'+stable_count/10);
        draw_result_char(panel_workspace,72,221,'0'+stable_count%10);
    } else {
        draw_result_char(panel_workspace,62,221,'-');
        draw_result_char(panel_workspace,72,221,'-');
    }
    fill_frame_index++;

    // Six-panel raster in the same 3x2 layout as render_hdmi_mosaic().
    const int column[4]={0,426,853,1280};
    for(int y=0;y<OUT_H;y++)for(int x=0;x<OUT_W;x++){
#pragma HLS PIPELINE II=1

        int row=y/320,col=(x<426?0:(x<853?1:2));int panel=row*3+col;
        int local_x=x-column[col],local_y=y-row*320;int pw=column[col+1]-column[col];
        RGB c=bilinear_panel(panel_workspace,panel,local_x,local_y,pw);
        // The Python renderer draws a dark 27-pixel header on every tile.
        if(local_y<27)c=RGB{24,24,24};
        mosaic_frame[y*OUT_W+x]=rgb_to_565(c);
    }
    // One-cycle completion pulse consumed by the PL result classifier.
    frame_done = 1;
}

