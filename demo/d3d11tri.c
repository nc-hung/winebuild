/* Minimal D3D11 triangle demo for testing Wine + DXVK.
 * Usage: d3d11tri.exe [seconds]   (default 10; 0 = run until closed)
 * Prints the DXGI adapter description so the GPU can be checked without the HUD. */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <stdlib.h>

static const char shader_src[] =
    "struct VSOut { float4 pos : SV_Position; float4 col : COLOR; };\n"
    "VSOut vs(uint id : SV_VertexID) {\n"
    "  float2 p[3] = { float2(0.0, 0.6), float2(0.6, -0.5), float2(-0.6, -0.5) };\n"
    "  float4 c[3] = { float4(1,0,0,1), float4(0,1,0,1), float4(0,0,1,1) };\n"
    "  VSOut o; o.pos = float4(p[id], 0, 1); o.col = c[id]; return o;\n"
    "}\n"
    "float4 ps(VSOut i) : SV_Target { return i.col; }\n";

static LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

static ID3DBlob *compile(const char *entry, const char *target)
{
    ID3DBlob *blob = NULL, *err = NULL;
    HRESULT hr = D3DCompile(shader_src, sizeof(shader_src) - 1, "tri.hlsl", NULL, NULL,
                            entry, target, 0, 0, &blob, &err);
    if (FAILED(hr)) {
        fprintf(stderr, "D3DCompile(%s) failed 0x%08lx: %s\n", entry, hr,
                err ? (const char *)ID3D10Blob_GetBufferPointer(err) : "");
        exit(2);
    }
    return blob;
}

int main(int argc, char **argv)
{
    double seconds = argc > 1 ? atof(argv[1]) : 10.0;
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = wndproc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursorA(NULL, (LPCSTR)IDC_ARROW);
    wc.lpszClassName = "d3d11tri";
    RegisterClassA(&wc);
    HWND hwnd = CreateWindowA("d3d11tri", "D3D11 triangle (DXVK test)", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              100, 100, 800, 600, NULL, NULL, wc.hInstance, NULL);

    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 2;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hwnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    ID3D11Device *dev; ID3D11DeviceContext *ctx; IDXGISwapChain *sc;
    D3D_FEATURE_LEVEL fl;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                               D3D11_SDK_VERSION, &sd, &sc, &dev, &fl, &ctx);
    if (FAILED(hr)) { fprintf(stderr, "D3D11CreateDeviceAndSwapChain failed 0x%08lx\n", hr); return 1; }

    IDXGIDevice *dxgidev; IDXGIAdapter *adapter; DXGI_ADAPTER_DESC ad;
    ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgidev);
    IDXGIDevice_GetAdapter(dxgidev, &adapter);
    IDXGIAdapter_GetDesc(adapter, &ad);
    printf("Adapter: %ls (vendor 0x%04x, device 0x%04x), feature level 0x%x\n",
           ad.Description, ad.VendorId, ad.DeviceId, fl);
    fflush(stdout);

    ID3DBlob *vsb = compile("vs", "vs_5_0"), *psb = compile("ps", "ps_5_0");
    ID3D11VertexShader *vs; ID3D11PixelShader *ps;
    ID3D11Device_CreateVertexShader(dev, ID3D10Blob_GetBufferPointer(vsb), ID3D10Blob_GetBufferSize(vsb), NULL, &vs);
    ID3D11Device_CreatePixelShader(dev, ID3D10Blob_GetBufferPointer(psb), ID3D10Blob_GetBufferSize(psb), NULL, &ps);

    ID3D11Texture2D *bb; ID3D11RenderTargetView *rtv;
    IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb);
    ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);

    D3D11_VIEWPORT vp = {0, 0, 800, 600, 0, 1};
    DWORD start = GetTickCount();
    unsigned frames = 0;
    MSG msg;
    for (;;) {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) goto done;
            TranslateMessage(&msg); DispatchMessageA(&msg);
        }
        float t = (GetTickCount() - start) / 1000.0f;
        float clear[4] = {0.1f, 0.1f, 0.15f + 0.1f * (float)(frames % 60) / 60.0f, 1.0f};
        ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
        ID3D11DeviceContext_RSSetViewports(ctx, 1, &vp);
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, clear);
        ID3D11DeviceContext_IASetPrimitiveTopology(ctx, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        ID3D11DeviceContext_VSSetShader(ctx, vs, NULL, 0);
        ID3D11DeviceContext_PSSetShader(ctx, ps, NULL, 0);
        ID3D11DeviceContext_Draw(ctx, 3, 0);
        IDXGISwapChain_Present(sc, 1, 0);
        frames++;
        if (seconds > 0 && t >= seconds) break;
    }
done:
    printf("Rendered %u frames in %.1fs\n", frames, (GetTickCount() - start) / 1000.0);
    return 0;
}
