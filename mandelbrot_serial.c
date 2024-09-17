#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <complex.h>

void generatePGM(const char *filename, int *pixelMap, int N, int maxVal)
{
    FILE *file = fopen(filename, "wb");
    if (file == NULL)
    {
        exit(1);
    }

    fprintf(file, "P5\n");
    fprintf(file, "%d %d\n", N, N);
    fprintf(file, "%d\n", maxVal);

    for (int i = 0; i < N; i++)
    {
        for (int j = 0; j < N; j++)
        {
            unsigned char pixel = (unsigned char)pixelMap[i * N + j];
            fwrite(&pixel, sizeof(unsigned char), 1, file);
        }
    }

    fclose(file);
}

int main(int argc, char **argv)
{
    char *endptr;
    if (argc != 6)
    {
        return 1;
    }
    int N = strtol(argv[1], &endptr, 10);
    double x_c = strtod(argv[2], &endptr);
    double y_c = strtod(argv[3], &endptr);
    double zoom = strtod(argv[4], &endptr);
    int cutoff = strtol(argv[5], &endptr, 10);

    int *pixelMap = malloc(N * N * sizeof(int));

    double distBetweenPoints = pow(2, -zoom);
    double length = distBetweenPoints * N;

    double xMin = x_c - (length / 2.0);
    double yMax = y_c + (length / 2.0);
    int iterations;
    double complex result;
    double x_p;
    double y_p;
    double complex c;
    for (int x = 0; x < N; x++)
    {
        for (int y = 0; y < N; y++)
        {
            iterations = 0;
            result = 0;
            x_p = x * distBetweenPoints + xMin;
            y_p = yMax - y * distBetweenPoints;
            c = x_p + y_p * I;
            while (cabs(result) <= 2 && iterations < cutoff)
            {
                result = result * result + c;
                iterations++;
            }
            pixelMap[y * N + x] = iterations;
        }
    }
    char *filename = malloc(sizeof(char) * 50);
    sprintf(filename, "mandel_%d_%.3lf_%.3lf_%.3lf_%d.pgm", N, x_c, y_c, zoom, cutoff);

    generatePGM(filename, pixelMap, N, cutoff);

    free(pixelMap);
    return 0;
}
