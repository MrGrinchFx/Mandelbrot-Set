#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <complex.h>
#include <mpi.h>

void generatePGM(const char *filename, int *pixelMap, int N, int maxVal)
{
    FILE *file = fopen(filename, "wb");
    if (file == NULL)
    {
        fprintf(stderr, "Error: Could not open file %s for writing\n", filename);
        exit(1);
    }

    // Write the header
    fprintf(file, "P5\n");
    fprintf(file, "%d %d\n", N, N);
    fprintf(file, "%d\n", maxVal);

    // Write the pixel data
    for (int i = 0; i < N * N; i++)
    {
        unsigned char pixel = (unsigned char)pixelMap[i];
        fwrite(&pixel, sizeof(unsigned char), 1, file);
    }

    fclose(file);
}

void computeMandelbrot(int N, double xMin, double yMax, double distBetweenPoints, int cutoff, int startRow, int numRows, int *subPixelMap)
{
    double complex c, z;
    int iterations;
    for (int y = startRow; y < startRow + numRows; y++)
    {
        for (int x = 0; x < N; x++)
        {
            double x_p = x * distBetweenPoints + xMin;
            double y_p = yMax - y * distBetweenPoints;
            c = x_p + y_p * I;
            z = 0;
            iterations = 0;
            while (cabs(z) <= 2 && iterations < cutoff)
            {
                z = z * z + c;
                iterations++;
            }
            subPixelMap[(y - startRow) * N + x] = iterations;
        }
    }
}

int main(int argc, char **argv)
{
    MPI_Init(&argc, &argv);

    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc != 6)
    {
        if (rank == 0)
        {
            fprintf(stderr, "Usage: %s <N> <x_center> <y_center> <zoom> <cutoff>\n", argv[0]);
        }
        MPI_Finalize();
        return 1;
    }

    int N = strtol(argv[1], NULL, 10);
    double x_c = strtod(argv[2], NULL);
    double y_c = strtod(argv[3], NULL);
    double zoom = strtod(argv[4], NULL);
    int cutoff = strtol(argv[5], NULL, 10);

    double distBetweenPoints = pow(2, -zoom);
    double length = distBetweenPoints * N;
    double xMin = x_c - (length / 2.0);
    double yMax = y_c + (length / 2.0);

    int rowsPerProcess = N / (size - 1);
    int remainingRows = N % (size - 1);

    int *sendCounts = malloc(size * sizeof(int));
    int *displs = malloc(size * sizeof(int));

    for (int i = 0; i < size; i++)
    {
        if (i == 0)
        {
            sendCounts[i] = 0; // Manager does not send data
            displs[i] = 0;
        }
        else
        {
            int startRow = (i - 1) * rowsPerProcess + (i <= remainingRows ? i - 1 : remainingRows);
            int numRows = rowsPerProcess + (i <= remainingRows ? 1 : 0);
            sendCounts[i] = numRows * N;
            displs[i] = startRow * N;
        }
    }

    int *pixelMap = NULL;
    if (rank == 0)
    {
        pixelMap = malloc(N * N * sizeof(int));
    }

    int startRow = (rank - 1) * rowsPerProcess + (rank <= remainingRows ? rank - 1 : remainingRows);
    int numRows = rowsPerProcess + (rank <= remainingRows ? 1 : 0);

    int *subPixelMap = malloc(numRows * N * sizeof(int));
    computeMandelbrot(N, xMin, yMax, distBetweenPoints, cutoff, startRow, numRows, subPixelMap);

    MPI_Gatherv(subPixelMap, sendCounts[rank], MPI_INT, pixelMap, sendCounts, displs, MPI_INT, 0, MPI_COMM_WORLD);

    if (rank == 0)
    {
        char filename[100];
        snprintf(filename, sizeof(filename), "mandel_%d_%.3lf_%.3lf_%.3lf_%d_mine.pgm", N, x_c, y_c, zoom, cutoff);
        generatePGM(filename, pixelMap, N, cutoff);
        free(pixelMap);
    }

    free(sendCounts);
    free(displs);
    free(subPixelMap);

    MPI_Finalize();
    return 0;
}
