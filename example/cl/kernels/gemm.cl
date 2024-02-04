// TODO: split-k


//    K     N        N
// M     K     =  M

//// CPU�汾
// for (i = 0; i < M; ++i) {
//     for (j = 0; j < N; ++j) {
//         for (k = 0; k < K; ++k) {
//             C[i*ldc + j] += A[i*lda + k] * B[k*ldb + j];
//         }
//     }
// }

// V1 ��ȫ���ڴ��ж�ȡ����Ҫ��������ݵ��Ĵ��������㡣ֱ�ӻ���CPU�汾����i��jѭ��ȥ����
// Kernel�����дʱʡ����i��jѭ������ʵ��i��jѭ����Ȼ�Ǵ��ڵģ�
// ��Ϊ�������ģ�����Ӳ����Դ��˵����ʱ��SM����������SM�ڻ�Ծwarp����Ҳ����
// ��Active Warp ������ȡ���� block ʹ�õ���Դ������������gpu�޷�һ�ν��������ݶ���ȡ����
// ����i��j����ѭ����Ҳ����һ�����Ⱥ�˳��ġ������ô�ʱ������ֱ������Ϊ����ѭ�����з�����
__kernel void GemmDeviceV1(const int M, const int N, const int K,
                           __global const float *A, const int lda,
                           __global const float *B, const int ldb,
                           __global float *C, const int ldc) {

    for (int gid_x = get_global_id(0), gid_y = get_global_id(1);
        gid_x < N && gid_y < M; 
        gid_x += get_global_size(0), gid_y += get_global_size(1)) {

        float c_sub_acc = 0;
        for (int k = 0; k < K; k++) {
            c_sub_acc += A[gid_y * lda + k] * B[k * ldb + gid_x];
        }
        C[gid_y * ldc + gid_x] = c_sub_acc;
    }
}

// v2
// v1�У������ݴ�ȫ���ڲ��аᵽ�Ĵ����н��м��㣬��Ϊ����������ѭ�����ο�CPU�汾������AB��������ݻ��ظ���ȡ��
// ����Խ�global memory ������һ���Լ��ص� local memory��ÿ�����ݴ�ȫ���ڴ��ȡ���൱��CPU������ѭ����
// �������������ݴӾֲ��ڴ��ж�ȡ���Ĵ������м��㣬
// ��������ѭ���ظ���ȡȫ���ڴ棬��Ϊ����ѭ��һ�ζ�ȡȫ���ڴ������ѭ���ظ���ȡ�ֲ��ڴ档
// ����ʡ��global memory��ȡ�Ĵ�����
#define BLOCK_SIDE_SIZE 16
__kernel void GemmDeviceV2(const int M, const int N, const int K,
                           __global const float *A, const int lda,
                           __global const float *B, const int ldb,
                           __global float *C, const int ldc) {

    __local float a_shared[BLOCK_SIDE_SIZE][BLOCK_SIDE_SIZE]; // cuda: __shared__ float a_shared[BLOCK_SIZE][BLOCK_SIZE];
    __local float b_shared[BLOCK_SIDE_SIZE][BLOCK_SIDE_SIZE]; // cuda: __shared__ float b_shared[BLOCK_SIZE][BLOCK_SIZE];

    for (int gid_x = get_global_id(0), gid_y = get_global_id(1);
        gid_x < N && gid_y < M; 
        gid_x += get_global_size(0), gid_y += get_global_size(1)) {

        int tid_x = get_local_id(0);
        int tid_y = get_local_id(1);

        float c_sub_acc = 0;
        // For blocks in grid.
        for (int bk = 0; bk < K; bk += BLOCK_SIDE_SIZE) {
            a_shared[tid_y][tid_x] = A[gid_y * lda + (bk + tid_x)];
            b_shared[tid_y][tid_x] = B[(bk + tid_y) * ldb + gid_x];
            // Wait for data to complete loading to Shared memory.
            barrier(CLK_LOCAL_MEM_FENCE); // cuda: __syncthreads()

            // For elements in a block.
            for (int k = 0; k < BLOCK_SIDE_SIZE; k++) {
                c_sub_acc += a_shared[tid_y][k] * b_shared[k][tid_x];
            }
            // To prevent the case from happening:
            // The next round of data is loaded when the data in share memory is not used up.
            barrier(CLK_LOCAL_MEM_FENCE); // cuda: __syncthreads()
        }

        C[gid_y * ldc + gid_x] += c_sub_acc;
    }
}

// v3 
// v2�У�ʹ�þֲ��ڴ������ȫ���ڴ�Ķ�η��ʣ�����ȫ���ڴ�ķ��ʴ������𵽼������á�
// ����Ϊʵ�ʼ�����Ҫ�Ƚ����ݶ�ȡ���Ĵ�������Ȼ�ֲ��ڴ���ʱ�ȫ���ڴ�첻�٣�Ҳ��Ȼ���ڲ��̵ĺ�ʱ��
// ���ڲ�ѭ����֪��һ�γ˷�����������ξֲ��ڴ�Ķ�ȡ��������ָ��ռ1/3�������·ô��ӳ��޷������ء�
// 
// ��Ϊ������ѭ���Ӿֲ��ڴ��ж�ȡ���ݣ������ʹ�ö���Ĵ�����Ϊ��һ�㼶�ڴ档
// �� v1 ����ȫ���ڴ� -> v2 ����ȫ���ڴ�+����ֲ��ڴ� -> v3 ����ȫ���ڴ�+����/step�ľֲ��ڴ�+����step�Ĵ������Ĵ����ɺ��ԣ�
// �� ������ʽ�ǽ����ݴӾֲ��ڴ��ȡʱ������1���̶߳�ȡK�����ݣ����1���̶߳�ȡstep*K�������Լ�step*step���Ӿ���˷���
//
// ��һ���̴߳���2*2��Ԫ�أ���Ӧʹ��ԭ��4����local memory
// local size ���䣬global size ������1/4�������߳������ٵ�1/4
//
// note: 1���̶߳�ȡK������ �� 1���̶߳�ȡstep*k������ ��������̫����죬��Ϊ���ݶ�ʱǰ�߿����̶߳࣬������Ҫ��ѯ������ͬһʱ��ȫ�������ꡣ
//       ����step*step�ļĴ����Ͼ���˷�, ÿ��Ԫ�ػᱻʹ��STEP�Σ��൱�ھֲ��ڴ�ķô�����STEP����
//       ��stepΪ2����A��B����Ӿֲ��ڴ浽�Ĵ����ķô�����ֱ���2�Σ���4�Σ�������Ҳ��2*2�Σ������ô��Ϊ1��1.
//       stepΪ4����ô�4+4�Σ�����4*4=16�Σ�����ô��Ϊ16/8
__kernel void GemmDeviceV3(const int M, const int N, const int K,
                           __global const float *A, const int lda,
                           __global const float *B, const int ldb,
                           __global float *C, const int ldc) {
    const int STEP = 2;
    float a_reg[STEP] = {0};
    float b_reg[STEP] = {0};    
    float sub_sum[STEP][STEP] = {{0}};
    __local float a_shared[BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];
    __local float b_shared[BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];

    for (int gid_x = get_global_id(0), gid_y = get_global_id(1);
        gid_x < N && gid_y < M; 
        gid_x += get_global_size(0), gid_y += get_global_size(1)) {

        int tid_x = get_local_id(0);
        int tid_y = get_local_id(1);

        // For blocks in grid.
        for (int bk = 0; bk < K; bk += BLOCK_SIDE_SIZE*STEP) {
            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                    a_shared[tid_y*STEP+si][tid_x*STEP+sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                    b_shared[tid_y*STEP+si][tid_x*STEP+sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
                }
            }
            barrier(CLK_LOCAL_MEM_FENCE); 
   
            // For elements in a block.
            for (int k = 0; k < BLOCK_SIDE_SIZE*STEP; k++) {
                // for (int si = 0; si < STEP; si++) {
                //     for (int sj = 0; sj < STEP; sj++) {
                //         sub_sum[si][sj] += a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                //     }
                // }

                for (int si=0; si < STEP; si++) {
                    a_reg[si] = a_shared[tid_y*STEP+si][k];
                    b_reg[si] = b_shared[k][tid_x*STEP+si];
                }
                // Both a_reg[si] and b_reg[sj] have been used STEP times.
                for (int si = 0; si < STEP; si++) {
                    for (int sj = 0; sj < STEP; sj++) {
                        sub_sum[si][sj] += a_reg[si] * b_reg[sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                    }
                }
            }
            barrier(CLK_LOCAL_MEM_FENCE); 
        }

        for (int i=0; i<STEP; i++) {
            for (int j=0; j<STEP; j++) {
                C[(gid_y*STEP+i) * ldc + gid_x*STEP+j] += sub_sum[i][j];
            }
        }
    }
}

// v4
// ����v3����һ������STEPΪ4�������ô��Ϊ(4*4)/(4+4)=16/8
// ���ǲ��ں����к�ʱ�Ը���v3���²��ǼĴ��������������¡�
__kernel void GemmDeviceV4(const int M, const int N, const int K,
                           __global const float *A, const int lda,
                           __global const float *B, const int ldb,
                           __global float *C, const int ldc) {

    const int STEP = 4;
    float a_reg[STEP] = {0};
    float b_reg[STEP] = {0};    
    float sub_sum[STEP][STEP] = {{0}};
    __local float a_shared[BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];
    __local float b_shared[BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];

    for (int gid_x = get_global_id(0), gid_y = get_global_id(1);
        gid_x < N && gid_y < M; 
        gid_x += get_global_size(0), gid_y += get_global_size(1)) {

        int tid_x = get_local_id(0);
        int tid_y = get_local_id(1);

        // For blocks in grid.
        for (int bk = 0; bk < K; bk += BLOCK_SIDE_SIZE*STEP) {
            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                    a_shared[tid_y*STEP+si][tid_x*STEP+sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                    b_shared[tid_y*STEP+si][tid_x*STEP+sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
                }
            }
            barrier(CLK_LOCAL_MEM_FENCE); 
   
            // For elements in a block.
            for (int k = 0; k < BLOCK_SIDE_SIZE*STEP; k++) {
                for (int si=0; si < STEP; si++) {
                    a_reg[si] = a_shared[tid_y*STEP+si][k];
                    b_reg[si] = b_shared[k][tid_x*STEP+si];
                }
                // Both a_reg[si] and b_reg[sj] have been used STEP times.
                for (int si = 0; si < STEP; si++) {
                    for (int sj = 0; sj < STEP; sj++) {
                        sub_sum[si][sj] += a_reg[si] * b_reg[sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                    }
                }
            }
            barrier(CLK_LOCAL_MEM_FENCE); 
        }

        for (int i=0; i<STEP; i++) {
            for (int j=0; j<STEP; j++) {
                C[(gid_y*STEP+i) * ldc + gid_x*STEP+j] += sub_sum[i][j];
            }
        }
    }
}

// https://zhuanlan.zhihu.com/p/657632577
// �ο�������Ԫ�� ��CUDA ����˷��ռ��Ż�ָ�ϡ�
// v5 
// ����v3����v3�����ݴ�ȫ���ڴ�->�ֲ��ڴ�->�Ĵ�����ſ�ʼ���㣬���߳��뵥�߳����ƣ�
// ����Ӳ����Դ����ֻ��5���̣߳���ͬʱ����0-4�����ݣ�5-10��������Ҫ��0-4�ŵ�ĳЩ���ݴ�������֮�󣬲��п���ȥִ���µ����ݡ�
// ��������Ҫ�������Ľ������д���������Ľ��������˲���Ҫ�ĺ�ʱ�ȴ���
// �� ->      -> д����  ->        ->  д����  ->        -> д
//       ����                ����                  ����
// ������ͷô�ָ���ͬʱִ�У���ʹ��double buffer / prefetch ���ڸ������ʱ����ɣ�
// ��0 ->  ��1  ->  д0����2  -> д1����3  ->  д2  -> д3
//        ����0      ����1        ����2       ����3
// ��һ�μ���0��Ҫ������0���˺�ſ�ʼ���㣬������0ʱ����ͬʱ��1���ڼ���0���˺󣬶�1Ҳ�����ˡ�
// ��1�ͼ���0֮���������������ɲο�CPU�༶��ˮ���е�д������ݳ�ͻ��������ʱ��ˮ�߸���Ч(ILPָ�����)��
// loadָ�����������ָ��ķ��䣬ʹ���㵥Ԫ�ŵø�����
// ͬʱʡ����һ��barrier(CLK_LOCAL_MEM_FENCE) / __syncthreads(), ���ٵȴ�ʱ�䡣
//
// ����ʵʩ��ʽ��
// 1) ����˫�ݾֲ��ڴ棬�������̣�ż����buffer0��������buffer1����buffer0�н��м���0��ͬʱ��buffer1�ж�1.
// 2����һ�����ݼ�������ѭ��֮ǰ�����һ�μ�������ѭ��֮��
//      (gmem0->smem0)   // first.  sync
//        for  (smem0->reg0) 
//             (reg0 compute)
//             (gmem1->smem1)  // sync
//      (reg1 compute)   // last
// 3) ���ڼ������һ�ηô�ʹ�õ�Shared Memory��ͬ�������ѭ����ÿ��ѭ��ֻ��Ҫһ��__syncthreads()����.
// 4) ����GPU������CPU����֧������ִ�У���ѭ������Ҫ�Ƚ���һ��ѭ��������Ҫ��Gloabal Memory�е�����load ���Ĵ�����
//    Ȼ����б��μ��㣬֮���ٽ�load���Ĵ����е�����д��Shared Memory��������LDGָ����Global Memory��loadʱ��
//    ����Ӱ�����FFMA����������ָ��� launch ִ�У�Ҳ�ʹﵽ��Double Buffering��Ŀ�ġ�
// 4.1) ��smem����reg�Ĵ����gmem���ص�smem�Ĵ������һ��ͬ���ڼ��ز��֡�
//      (gmem0->smem0)   // first. sync
//      (smem0->reg0)    
//        for  (reg0 compute)
//             (gmem1->smem1)  // sync
//             (smem1->reg1) 
//      (reg1 compute)   // last  
// 4.2��gmem -> smem �䱾����ʵ�� gmem -> reg(ldg_reg) -> smem, ������зֽ⣬�������
//      (gmem0->ldg_reg0)   // first
//      (ldg_reg0->smem0)   // sync
//      (smem0->reg0) 
//        for  (reg0 compute)
//             (gmem1->ldg_reg1) 
//             (ldg_reg1->smem1) // sync
//             (smem1->reg1) 
//      (reg1 compute)   // last  
//      ʵ�ֵ�������Կ������㲿���õ�reg0��reg0����һ���smem0->reg0�õ�������������
// 
// 4.3�����ڲ�ѭ���� gmem -> ldg_reg �ŵ� �����ǰ�棬ldg_reg -> smem �ŵ�����ĺ��档
//      ��gmem��ȡ��smemд����һ�������smem��ȡ�ͼ���Ҳ��һ������������Լ�����
//      (gmem0->ldg_reg0)   // first
//      (ldg_reg0->smem0)   // sync
//      (smem0->reg0) 
//        for  (gmem1->ldg_reg1) 
//             (reg0 compute)
//             (ldg_reg1->smem1) // sync
//             (smem1->reg1) 
//      (reg1 compute)   // last  
//

// �м�汾������ѭ����ֳ����� ʵ������� 1��2 �� 3
__kernel void GemmDeviceV5_0(const int M, const int N, const int K,
                           __global const float *A, const int lda,
                           __global const float *B, const int ldb,
                           __global float *C, const int ldc) {

    const int STEP = 2;
    float a_reg[2][STEP] = {0};
    float b_reg[2][STEP] = {0};    
    float sub_sum[2][STEP][STEP] = {{{0}}};
    __local float a_shared[2][BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];
    __local float b_shared[2][BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];

    for (int gid_x = get_global_id(0), gid_y = get_global_id(1);
        gid_x < N && gid_y < M; 
        gid_x += get_global_size(0), gid_y += get_global_size(1)) {

        int tid_x = get_local_id(0);
        int tid_y = get_local_id(1);

        // The first fetching.
        int bk = 0;
        for (int si = 0; si < STEP; si++) {
            for (int sj = 0; sj < STEP; sj++) {
                // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                a_shared[0][tid_y*STEP+si][tid_x*STEP+sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                b_shared[0][tid_y*STEP+si][tid_x*STEP+sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE); 

        // Main loop.
        int  block_step = BLOCK_SIDE_SIZE*STEP;
        int buffer_id = 0;
        int buffer_next_id = 1;
        int temp_id;
        for (bk = block_step; bk < K; bk += block_step) {
            // For elements in a block.
            for (int k = 0; k < block_step; k++) {
                for (int si=0; si < STEP; si++) {
                    a_reg[buffer_id][si] = a_shared[buffer_id][tid_y*STEP+si][k];
                    b_reg[buffer_id][si] = b_shared[buffer_id][k][tid_x*STEP+si];
                }
                // Both a_reg[si] and b_reg[sj] have been used STEP times.
                for (int si = 0; si < STEP; si++) {
                    for (int sj = 0; sj < STEP; sj++) {
                        sub_sum[buffer_id][si][sj] += a_reg[buffer_id][si] * b_reg[buffer_id][sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                    }
                }
            }

            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                    a_shared[buffer_next_id][tid_y*STEP+si][tid_x*STEP+sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                    b_shared[buffer_next_id][tid_y*STEP+si][tid_x*STEP+sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
                }
            }
            barrier(CLK_LOCAL_MEM_FENCE);

            temp_id = buffer_next_id;
            buffer_next_id = buffer_id;
            buffer_id = temp_id;
        }

        // The last computing
        for (int k = 0; k < block_step; k++) {
            for (int si=0; si < STEP; si++) {
                a_reg[buffer_id][si] = a_shared[buffer_next_id][tid_y*STEP+si][k];
                b_reg[buffer_id][si] = b_shared[buffer_next_id][k][tid_x*STEP+si];
            }
            // Both a_reg[si] and b_reg[sj] have been used STEP times.
            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    sub_sum[buffer_id][si][sj] += a_reg[buffer_id][si] * b_reg[buffer_id][sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                }
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE); 

        for (int i=0; i<STEP; i++) {
            for (int j=0; j<STEP; j++) {
                C[(gid_y*STEP+i) * ldc + gid_x*STEP+j] += sub_sum[0][i][j] + sub_sum[1][i][j];
            }
        }
    }
}

// �м�汾��ʵ��4.1��4.2
__kernel void GemmDeviceV5_1(const int M, const int N, const int K,
                           __global const float *A, const int lda,
                           __global const float *B, const int ldb,
                           __global float *C, const int ldc) {

    const int STEP = 2;
    float a_ldg_reg[2][2] = {0};
    float b_ldg_reg[2][2] = {0}; 

    float a_reg[2][STEP] = {0};
    float b_reg[2][STEP] = {0};    
    float sub_sum[2][STEP][STEP] = {{{0}}};
    __local float a_shared[2][BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];
    __local float b_shared[2][BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];

    int  block_step = BLOCK_SIDE_SIZE*STEP;
    for (int gid_x = get_global_id(0), gid_y = get_global_id(1);
        gid_x < N && gid_y < M; 
        gid_x += get_global_size(0), gid_y += get_global_size(1)) {

        int tid_x = get_local_id(0);
        int tid_y = get_local_id(1);

        // The first fetching.
        int bk = 0;
        for (int si = 0; si < STEP; si++) {
            for (int sj = 0; sj < STEP; sj++) {
                a_ldg_reg[si][sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                b_ldg_reg[si][sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
            }
        }
        for (int si = 0; si < STEP; si++) {
            for (int sj = 0; sj < STEP; sj++) {
                // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                a_shared[0][tid_y*STEP+si][tid_x*STEP+sj] = a_ldg_reg[si][sj];
                b_shared[0][tid_y*STEP+si][tid_x*STEP+sj] = b_ldg_reg[si][sj];
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE);

        for (int k = 0; k < block_step; k++) {
            for (int si=0; si < STEP; si++) {
                a_reg[0][si] = a_shared[0][tid_y*STEP+si][k];
                b_reg[0][si] = b_shared[0][k][tid_x*STEP+si];
            }
        }

        // Main loop.
        int buffer_id = 0;
        int buffer_next_id = 1;
        int temp_id;
        for (bk = block_step; bk < K; bk += block_step) {
            // For elements in a block.
            for (int k = 0; k < block_step; k++) {
                // Both a_reg[si] and b_reg[sj] have been used STEP times.
                for (int si = 0; si < STEP; si++) {
                    for (int sj = 0; sj < STEP; sj++) {
                        sub_sum[buffer_id][si][sj] += a_reg[buffer_id][si] * b_reg[buffer_id][sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                    }
                }
            }

            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                    a_ldg_reg[si][sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                    b_ldg_reg[si][sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
                }
            }
            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                    a_shared[buffer_next_id][tid_y*STEP+si][tid_x*STEP+sj] = a_ldg_reg[si][sj];
                    b_shared[buffer_next_id][tid_y*STEP+si][tid_x*STEP+sj] = b_ldg_reg[si][sj];
                }
            }
            barrier(CLK_LOCAL_MEM_FENCE);

            for (int k = 0; k < block_step; k++) {
                for (int si=0; si < STEP; si++) {
                    a_reg[buffer_next_id][si] = a_shared[buffer_next_id][tid_y*STEP+si][k];
                    b_reg[buffer_next_id][si] = b_shared[buffer_next_id][k][tid_x*STEP+si];
                }
            }
            temp_id = buffer_next_id;
            buffer_next_id = buffer_id;
            buffer_id = temp_id;
        }

        // The last computing
        for (int k = 0; k < block_step; k++) {
            // Both a_reg[si] and b_reg[sj] have been used STEP times.
            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    sub_sum[buffer_id][si][sj] += a_reg[buffer_id][si] * b_reg[buffer_id][sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                }
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE); 

        for (int i=0; i<STEP; i++) {
            for (int j=0; j<STEP; j++) {
                C[(gid_y*STEP+i) * ldc + gid_x*STEP+j] += sub_sum[0][i][j] + sub_sum[1][i][j];
            }
        }
    }
}


// v5 prefetch / double buffering ʵ���հ棨ʵ��4.3��
__kernel void GemmDeviceV5_2(const int M, const int N, const int K,
                           __global const float *A, const int lda,
                           __global const float *B, const int ldb,
                           __global float *C, const int ldc) {

    const int STEP = 2;
    float a_ldg_reg[STEP][STEP] = {0};
    float b_ldg_reg[STEP][STEP] = {0}; 

    float a_reg[2][STEP] = {0};
    float b_reg[2][STEP] = {0};    
    float sub_sum[2][STEP][STEP] = {{{0}}};
    __local float a_shared[2][BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];
    __local float b_shared[2][BLOCK_SIDE_SIZE*STEP][BLOCK_SIDE_SIZE*STEP];

    int  block_step = BLOCK_SIDE_SIZE*STEP;
    for (int gid_x = get_global_id(0), gid_y = get_global_id(1);
        gid_x < N && gid_y < M; 
        gid_x += get_global_size(0), gid_y += get_global_size(1)) {

        int tid_x = get_local_id(0);
        int tid_y = get_local_id(1);

        // The first fetching.
        int bk = 0;
        for (int si = 0; si < STEP; si++) {
            for (int sj = 0; sj < STEP; sj++) {
                a_ldg_reg[si][sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                b_ldg_reg[si][sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
            }
        }
        for (int si = 0; si < STEP; si++) {
            for (int sj = 0; sj < STEP; sj++) {
                // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                a_shared[0][tid_y*STEP+si][tid_x*STEP+sj] = a_ldg_reg[si][sj];
                b_shared[0][tid_y*STEP+si][tid_x*STEP+sj] = b_ldg_reg[si][sj];
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE);

        for (int k = 0; k < block_step; k++) {
            for (int si=0; si < STEP; si++) {
                a_reg[0][si] = a_shared[0][tid_y*STEP+si][k];
                b_reg[0][si] = b_shared[0][k][tid_x*STEP+si];
            }
        }

        // Main loop.
        int buffer_id = 0;
        int buffer_next_id = 1;
        int temp_id;
        for (bk = block_step; bk < K; bk += block_step) {

            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                    a_ldg_reg[si][sj] = A[(gid_y*STEP+si) * lda + (bk + tid_x*STEP+sj)];
                    b_ldg_reg[si][sj] = B[(bk + (tid_y*STEP+si)) * ldb + gid_x*STEP+sj];
                }
            }

            // For elements in a block.
            for (int k = 0; k < block_step; k++) {
                // Both a_reg[si] and b_reg[sj] have been used STEP times.
                for (int si = 0; si < STEP; si++) {
                    for (int sj = 0; sj < STEP; sj++) {
                        sub_sum[buffer_id][si][sj] += a_reg[buffer_id][si] * b_reg[buffer_id][sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                    }
                }
            }

            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    // 0->01, 1->23 => 0*2+0/0*2+1, 1*2+0/1*2+1
                    a_shared[buffer_next_id][tid_y*STEP+si][tid_x*STEP+sj] = a_ldg_reg[si][sj];
                    b_shared[buffer_next_id][tid_y*STEP+si][tid_x*STEP+sj] = b_ldg_reg[si][sj];
                }
            }
            barrier(CLK_LOCAL_MEM_FENCE);

            for (int k = 0; k < block_step; k++) {
                for (int si=0; si < STEP; si++) {
                    a_reg[buffer_next_id][si] = a_shared[buffer_next_id][tid_y*STEP+si][k];
                    b_reg[buffer_next_id][si] = b_shared[buffer_next_id][k][tid_x*STEP+si];
                }
            }
            temp_id = buffer_next_id;
            buffer_next_id = buffer_id;
            buffer_id = temp_id;
        }

        // The last computing
        for (int k = 0; k < block_step; k++) {
            // Both a_reg[si] and b_reg[sj] have been used STEP times.
            for (int si = 0; si < STEP; si++) {
                for (int sj = 0; sj < STEP; sj++) {
                    sub_sum[buffer_id][si][sj] += a_reg[buffer_id][si] * b_reg[buffer_id][sj]; // a_shared[tid_y*STEP+si][k] * b_shared[k][tid_x*STEP+sj];
                }
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE); 

        for (int i=0; i<STEP; i++) {
            for (int j=0; j<STEP; j++) {
                C[(gid_y*STEP+i) * ldc + gid_x*STEP+j] += sub_sum[0][i][j] + sub_sum[1][i][j];
            }
        }
    }
}