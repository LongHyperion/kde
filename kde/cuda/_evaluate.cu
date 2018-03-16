#include <stdio.h>
#include <cuda_runtime.h>
#include "kernels.cuh"
#include "distance.cuh"

// kernel options
enum kernelopt{BUMP, COSINE, EPANECHNIKOV, GAUSSIAN, 
               LOGISTIC, QUARTIC, TOPHAT, TRIANGLE, TRICUBE};
enum metricopt{EUCLIDEAN_DISTANCE, EUCLIDEAN_DISTANCE_NTORUS};

// Types for device function pointers
typedef double (*KERNELFUNC_t)(double);

// Cuda kernel for evaluating kernel density estimate
__global__ void
_evaluate_cu(const double* query_points, 
             const double* training_points, 
             const double* weights,
             enum metricopt metric_idx,
             enum kernelopt kernel_idx,
             double h, 
             double* result,
             int nquery, int ntrain, int ndim)
{
  /* query_points and training_points are "2d" arrays indexed as
   *   "query_points[i,j]" = query_points[ndim*i+j]
   */
        

  // Each thread operates on its own element of query_points
  int iquery = blockDim.x * blockIdx.x + threadIdx.x;
  int itrain;

  switch(metricopt) {
    case EUCLIDEAN_DISTANCE:
      distance = euclidean_distance;
    case EUCLIDEAN_DISTANCE_NTORUS:
      distance = euclidean_distance_ntorus;
  }

  KERNELFUNC_t kernel;
  switch(kernelopt) {
    case BUMP:
      kernel = bump;
    case COSINE:
      kernel = cosine_kernel;
    case EPANECHNIKOV:
      kernel = epanechnikov;
    case GAUSSIAN:
      kernel = gaussian;
    case LOGISTIC:
      kernel = logistic;
    case QUARTIC:
      kernel = quartic;
    case TOPHAT:
      kernel = tophat;
    case TRIANGLE:
      kernel = triangle;
    case TRICUBE:
      kernel = TRICUBE;
  }

  if (iquery<nquery) {
    for (itrain=0;itrain<ntrain;itrain++) {
      // Recall that training_points and query_points are 2d arrays that we are
      // thinking of as 1d arrays.  That is, training_points[ndim*itrain] is the
      // ``itrain``th  vector of length ``ndim``
      result[iquery] += weights[itrain] * kernel(distance(training_points[ndim*itrain], query_points[ndim*iquery], ndim)/h);
    }
    result[iquery] /= h;
  }
}

// Wrapper for cuda kernel
void
cuda_evaluate(const double* query_points,
              const double* training_points, 
              const double* weights,
              char* metric_s,
              char* kernel_s,
              double h, 
              double* result,
              int nquery, int ntrain, int ndim)
{
  // query_points and training_points are "2d" arrays indexed as
  //    "query_points[i,j]" = query_points[ndim*i+j]

  // Parse ``metric_s`` and ``kernel_func_s``
  enum metricopt metric;
  if strcmp(metric_s, "euclidean_distance") {
    metric = EUCLIDEAN_DISTANCE;
  } else if strcmp(metric_s, "eucldiean_distance_ntorus") {
    metric = EUCLIDEAN_DISTANCE_NTORUS;
  } else {
    printf("Metric ``%s`` not implemented.", metric_s);
    exit(EXIT_FAILURE);
  }
  
  enum kernelopt kernel
  if strcmp(kernel_s, "bump") {
    kernel = BUMP;
  } else if strcmp(kernel_s, "cosine") {
    kernel = COSINE;
  } else if strcmp(kernel_s, "epanechnikov") {
    kernel = EPANECHNIKOV;
  } else if strcmp(kernel_s, "gaussian") {
    kernel = GAUSSIAN;
  } else if strcmp(kernel_s, "logistic") {
    kernel = LOGISTIC;
  } else if strcmp(kernel_s, "quartic") {
    kernel = QUARTIC;
  } else if strcmp(kernel_s, "tophat") {
    kernel = TOPHAT;
  } else if strcmp(kernel_s, "triangle") {
    kernel = TRIANGLE;
  } else if strcmp(kernel_s, "tricube") {
    kernel = TRICUBE;
  } else {
    printf("Kernel ``%s`` not implemented.", kernel_s);
    exit(EXIT_FAILURE);
  }


  // Allocate device memory 
  double *d_query_points = NULL;
  err = cudaMalloc((void **)&d_query_points, ndim*nquery*sizeof(double));
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to allocate device array ``query_points`` (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }
  double *d_training_points = NULL;
  err = cudaMalloc((void **)&d_training_points, ndim*ntrain*sizeof(double));
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to allocate device array ``training_points`` (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }
  double *d_result = NULL;
  err = cudaMalloc((void **)&d_result, nquery*sizeof(double));
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to allocate device array ``result`` (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }
  double *d_weights = NULL;
  err = cudaMalloc((void **)&d_weights, ntrain*sizeof(double));
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to allocate device array ``weights`` (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }

  // Copy ``query_points`` and ``training_points`` into device memory
  err = cudaMemcpy(d_query_points, query_points, nquery*sizeof(double), cudaMemcpyHostToDevice);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to copy array ``query_points`` from host to device (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }
  err = cudaMemcpy(d_training_points, training_points, ntrain*sizeof(double), cudaMemcpyHostToDevice);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to copy array ``training_points`` from host to device (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }
  err = cudaMemcpy(d_weights, weights, ntrain*sizeof(double), cudaMemcpyHostToDevice);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to copy array ``weights`` from host to device (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }

  // Initialize ``result`` and ``d_result`` to 0
  int i;
  for (i=0;i<nquery;i++){
    result[i] = 0;
  }
  err = cudaMemcpy(d_result, result, nquery*sizeof(double), cudaMemcpyHostToDevice);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to copy array ``result`` from host to device (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }

  // Run the cuda kernel
  int threadsPerBlock = 256;
  int blocksPerGrid =(nquery + threadsPerBlock - 1) / threadsPerBlock;
  printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
  _evaluate_cu<<<blocksPerGrid, threadsPerBlock>>>(d_query_points, d_training_points, d_weights, metric, kernel, h, d_result, nquery, ntrain, ndim);
  err = cudaGetLastError();
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to launch kernel (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }

  // Copy the result vector from device to host
  err = cudaMemcpy(result, d_result, nquery*sizeof(double), cudaMemcpyDeviceToHost);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to copy result from device to host (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }

  err = cudaFree(d_query_points);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to free device array ``d_query_points`` (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }

  err = cudaFree(d_training_points);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to free device array ``d_training_points`` (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }

  err = cudaFree(d_result);
  if (err != cudaSuccess) {
    fprintf(stderr, "Failed to free device array ``d_result`` (error code %s)!\n", cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }
}

