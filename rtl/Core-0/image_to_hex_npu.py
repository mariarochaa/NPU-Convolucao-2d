#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
import argparse


def convert_image(input_path, output_path, width, height,
                  invert=False, threshold=None,
                  flatten='row-major', ext_mode='both'):
    # Abre imagem, converte para escala de cinza e redimensiona
    img = Image.open(input_path).convert('L').resize((width, height))

    # Opcional: binarização
    if threshold is not None:
        img = img.point(lambda p: 255 if p >= threshold else 0)

    # Salvar a imagem já tratada (28x28, escala de cinza)
    base = Path(output_path)
    preview_path = base.parent / (base.stem + '_28x28.png')
    img.save(preview_path)

    # Pixels em ordem raster (linha por linha)
    pixels = list(img.getdata())

    # Opcional: inverter (branco <-> preto)
    if invert:
        pixels = [255 - p for p in pixels]

    if flatten != 'row-major':
        raise ValueError('Atualmente apenas row-major é suportado.')

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Tipos de saída: .hex, .mem ou ambos
    targets = []
    if ext_mode in ('hex', 'both'):
        targets.append(output_path.with_suffix('.hex'))
    if ext_mode in ('mem', 'both'):
        targets.append(output_path.with_suffix('.mem'))

    # 1 pixel por linha, em hexadecimal, compatível com $readmemh
    for target in targets:
        with open(target, 'w', encoding='utf-8') as f:
            for px in pixels:
                f.write(f'{px:02x}\n')

    # Metadados opcionais
    meta_path = output_path.with_suffix('.txt')
    with open(meta_path, 'w', encoding='utf-8') as f:
        f.write(f'input={input_path}\n')
        f.write(f'width={width}\n')
        f.write(f'height={height}\n')
        f.write(f'pixels={len(pixels)}\n')
        f.write(f'invert={invert}\n')
        f.write(f'threshold={threshold}\n')
        f.write(f'flatten={flatten}\n')
        f.write('format=one-byte-per-line\n')
        f.write('compatible_with=$readmemh\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Converte imagem para .hex/.mem compatível com $readmemh para o projeto NPU-Convolucao-2d.'
    )
    parser.add_argument('input', help='Caminho da imagem de entrada')
    parser.add_argument('output', help='Prefixo do arquivo de saída (sem extensão obrigatória)')
    parser.add_argument('--width', type=int, default=28,
                        help='Largura da imagem final (default: 28)')
    parser.add_argument('--height', type=int, default=28,
                        help='Altura da imagem final (default: 28)')
    parser.add_argument('--invert', action='store_true',
                        help='Inverte os níveis de cinza (0↔255)')
    parser.add_argument('--threshold', type=int, default=None,
                        help='Binariza a imagem usando limiar de 0 a 255')
    parser.add_argument('--ext', choices=['hex', 'mem', 'both'],
                        default='both', help='Tipos de arquivo a gerar')
    args = parser.parse_args()

    convert_image(
        input_path=args.input,
        output_path=args.output,
        width=args.width,
        height=args.height,
        invert=args.invert,
        threshold=args.threshold,
        ext_mode=args.ext,
    )