module functions_m
use f95_precision
use lapack95
use blas95
use omp_lib
use types_m
use parameters_m
use constants_m !usa as constantes do constants_m => variaveis globais.

implicit none

public

contains

        
pure real function soma_elemento(ham_size, i1, i2, matriz)
!funcao para somar os elementos \sum_n Gamma(a, n, n, b)
implicit none
integer, INTENT(IN) :: ham_size, i1, i2
real*8, DIMENSION(ham_size, ham_size, ham_size, ham_size), INTENT(IN) :: matriz


real*8 :: temporary
integer :: i
temporary = 0.d0

do i = 1, ham_size
    temporary = temporary + matriz(i1, i, i, i2)
enddo

soma_elemento = temporary
return
end function soma_elemento


subroutine build_ovlp_pop(dims, ovlpm, rhom, pop) 
implicit none
integer, intent(in) :: dims
real*8, dimension(dims, dims), intent(in) :: ovlpm 
complex*16, dimension(dims, dims), intent(in) :: rhom
complex*16, dimension(:, :), allocatable, intent(out) :: pop

allocate(pop(dims, dims), source = (0.d0, 0.d0) ) 

pop = ( matmul(rhom, ovlpm) + matmul(ovlpm, rhom) ) / 2.d0

return 
end subroutine build_ovlp_pop



subroutine monta_rho(rho_size, vector, rho_matrix)
  !---- subrotina para montar uma matriz no tipo RHO ou RHOPONTO dado um vetor linha Y ou YP ---
  !A MATRIZ RHO FICA    RHO = (y(1) y(4) y(5)) + i (0    y(7) y(8) ) ou seja, temos dimensao*dimensao = 9 variavies
  !COMO (EX 3X3):             (y(4) y(2) y(6))     (y(7)  0   y(9) )          para resolver
  !                           (y(5) y(6) y(3))     (y(8) y(9)  0   )

implicit none
integer, intent(in) :: rho_size
real*8, intent(in) :: vector(rho_size*rho_size)
complex*16, intent(out) :: rho_matrix(rho_size, rho_size)
real*8 :: matriz_real(rho_size, rho_size), matriz_imag(rho_size, rho_size)

integer :: ndim  !numero de eq. pra resolver na matriz rho_real


rho_matrix = 0.d0 + zi * 0.d0
ndim = ((rho_size*(rho_size + 1)) / 2) !numero de eq. pra resolver na matriz rho_real
matriz_real = 0.d0 
matriz_imag = 0.d0


!--- PARTE DIAGONAL REAL ---
!forall(i=1:rho_size) matriz_real(i, i) = vector(i)

do i = 1, rho_size
  matriz_real(i, i) = vector(i)
enddo


!--- PARTE NÃO DIAGONAL REAL ---
k = rho_size + 1
do j = 1, rho_size
  do i = 1, rho_size
    if (i > j) then
     matriz_real(i, j) = vector(k)
     matriz_real(j, i) = matriz_real(i, j)
     k = k + 1
    endif
    enddo
enddo
!----------------------

!--- PARTE NÃO DIAGONAL IMAGINÁRIA ---
k = ndim + 1
do j = 1, rho_size
  do i = 1, rho_size
    if (i > j) then
     matriz_imag(i, j) = vector(k)
     matriz_imag(j, i) = - matriz_imag(i, j)
     k = k + 1
   endif
   enddo
enddo

forall(i = 1:rho_size) matriz_imag(i, i) = 0.d0 
!---------------------------

rho_matrix = matriz_real + zi * matriz_imag


do j = 1, rho_size
  do i = 1, rho_size
    if (i > j) then
        if ( matriz_real(i, j) /= matriz_real(j, i) ) then
               print*, "RHO NÃO ESTÁ HERMITIANO - PARTE REAL DIFERENTE"
        else if (matriz_imag(i, j) /= -matriz_imag(j, i) ) then
               print*, "RHO NÃO ESTÁ HERMITIANO - PARTE IMAGINARIA DIFERENTE"
               stop 
        endif
    endif
  enddo
enddo 


return
end subroutine monta_rho


!---- subrotina para montar um vetor do tipo Y OU YP  dado uma matriz do tipo RHO OU RHO PONTO ---
! O VETOR Y FICA        y(1) = rho_real(1, 1),  y(4) = rho_real(2, 1), y(7) = rho_imag(2, 1)
! ESCRITO NESSA FORMA   y(2) = rho_real(2, 2),  y(5) = rho_real(3, 1), y(8) = rho_imag(3, 1)
! COMO: (EX 3X3):       y(3) = rho_real(3, 3),  y(6) = rho_real(3, 2), y(9) = rho_imag(3, 2)


subroutine monta_y(rho_size, rho_matrix, vector)
implicit none
integer, intent(in) :: rho_size
complex*16, intent(in) :: rho_matrix(rho_size, rho_size)
real*8, intent(out) :: vector(rho_size * rho_size)

integer :: ndim  !numero de eq. pra resolver na matriz rho_real
real*8 :: matriz_real(rho_size, rho_size), matriz_imag(rho_size, rho_size)


ndim = ((rho_size*(rho_size + 1)) / 2) !numero de eq. pra resolver na matriz rho_real

!--- PARTE DIAGONAL REAL ---
forall(k=1:rho_size) vector(k) = real(rho_matrix(k, k))
!---------------------

!--- PARTE NÃO DIAGONAL REAL ---
k = rho_size + 1
do j = 1, rho_size
  do i = 1, rho_size
    if (i > j) then
     vector(k) = real(rho_matrix(i, j))
     k = k + 1
    endif
   enddo
enddo
!----------------------

!--- PARTE NÃO DIAGONAL IMAGINÁRIA ---
k = ndim + 1
do j = 1, rho_size
   do i = 1, rho_size
    if (i > j) then
     vector(k) = aimag(rho_matrix(i, j))
     k = k + 1
   endif
   enddo
enddo
!---------------------------

return

end subroutine monta_y

subroutine rho_matrix_to_pop(nstates, rho_size, rho_matrix, pop_matrix)
!subroutina que devolvolve a populacao do  sitio, ou seja
!matriz_pop(3, 1) = real(rho(3, 3)), matriz_pop(nrows, ncolumns) = real(rho(nm_rows*nm_columns, nm_rows*nm_columns))

implicit none
integer, intent(in) :: nstates, rho_size
complex*16, intent(in) :: rho_matrix(rho_size, rho_size)
real*8, intent(out) :: pop_matrix(nm_rows, nm_columns)

REAL*8 :: soma_temp

pop_matrix = 0.d0

soma_temp = 0.d0
k = 1
do j = 1, nm_columns !-1 !vetor coluna que vai pegar os elementos da diagional principal do rho
  do i = 1, nm_rows
    do l = 1, nstates
      soma_temp = soma_temp + real(rho_matrix(k, k))
      k = k + 1
    enddo
    pop_matrix(i, j) = soma_temp
    soma_temp = 0.d0
  enddo
enddo

return
end subroutine rho_matrix_to_pop

subroutine rhosite_TO_rhoham(rhosize, EGvectors, transpose_EGvectors, rhosite, rhoham)
implicit none
INTEGER, INTENT(IN) :: rhosize
REAL*8, DIMENSION(rhosize, rhosize), INTENT(IN) :: EGvectors, transpose_EGvectors
COMPLEX*16, DIMENSION(rhosize, rhosize), INTENT(IN) :: rhosite
COMPLEX*16, DIMENSION(rhosize, rhosize), INTENT(OUT) :: rhoham
complex*16, dimension(:, :), allocatable :: temporaria

complex*16, dimension(:, :), allocatable :: tempEGvectors, temptranspose_EGvectors

allocate(temporaria(rhosize, rhosize), source = (0.d0, 0.d0) )
allocate(tempEGvectors(rhosize, rhosize), source = (0.d0, 0.d0) ) 
allocate(temptranspose_EGvectors(rhosize, rhosize), source = (0.d0, 0.d0) ) 

tempEGvectors = EGvectors + zi * 0.d0
temptranspose_EGvectors = transpose_EGvectors + zi * 0.d0


call gemm(temptranspose_EGvectors, rhosite, temporaria)
call gemm(temporaria, tempEGvectors, rhoham) 

!temporaria = matmul(transpose_EGvectors, rhosite)
!rhoham = matmul(temporaria, EGvectors)


deallocate(temporaria, tempEGvectors, temptranspose_EGvectors) 
return
end subroutine rhosite_TO_rhoham


subroutine rhoham_TO_rhosite(rhosize, EGvectors, transpose_EGvectors, rhoham, rhosite)
implicit none
INTEGER, INTENT(IN) :: rhosize
REAL*8, DIMENSION(rhosize, rhosize), INTENT(IN) :: EGvectors, transpose_EGvectors
COMPLEX*16, DIMENSION(rhosize, rhosize), INTENT(in) :: rhoham
COMPLEX*16, DIMENSION(rhosize, rhosize), INTENT(OUT) :: rhosite
complex*16, dimension(:, :), allocatable :: temporaria

complex*16, dimension(:, :), allocatable :: tempEGvectors, temptranspose_EGvectors


allocate(temporaria(rhosize, rhosize), source = (0.d0, 0.d0) )
allocate(tempEGvectors(rhosize, rhosize), source = (0.d0, 0.d0) ) 
allocate(temptranspose_EGvectors(rhosize, rhosize), source = (0.d0, 0.d0) ) 


tempEGvectors = EGvectors + zi * 0.d0
temptranspose_EGvectors = transpose_EGvectors + zi * 0.d0



call gemm(tempEGvectors, rhoham, temporaria)
call gemm(temporaria, temptranspose_EGvectors, rhosite) 

!temporaria = matmul(EGvectors, rhoham)
!rhosite = matmul(temporaria, transpose_EGvectors)



deallocate(temporaria, tempEGvectors, temptranspose_EGvectors) 
return
end subroutine rhoham_TO_rhosite




subroutine printa_resultado(nstates, rho_size, nm_arquivo, t, rho_matrix)
!SUBROUTINE PARA ESCREVER OS RESULTADOS DO RHO SOMANDO OS ESTADOS PARA CADA SITIO
!OU SEJA, PARA NSTATES = 3, PROB DE ENCONTRARMOS O ELETRON NO SITIO 1 = RHO(1,1)+RHO(2,2)+RHO(3,3)

implicit none
integer, intent(in) :: nstates, rho_size, nm_arquivo
real*8, intent(in) :: t
complex*16, intent(in) :: rho_matrix(rho_size, rho_size)

!real*8 :: matriz_temporaria(dimensao-1)
real*8, DIMENSION(:), ALLOCATABLE :: matriz_temporaria
real*8 :: temp_soma
character (len=90) :: filename
integer :: verificador, counter

ALLOCATE(matriz_temporaria(nqdots), source = 0.d0) !matriz  temporaria guarda as populacoes de cada sitio

write(filename, "(A5, I2)") "fort.",nm_arquivo

counter = 1
temp_soma = 0.d0
do  i = 1, nsites  !-1 !vetor coluna que vai pegar os elementos da diagional principal do rho
  do j = 1, nstates
    temp_soma = real(rho_matrix(counter, counter)) + temp_soma
    counter = counter + 1
  enddo
  verificador = int(temp_soma)
  if (verificador >= 5) then
    print*, "As populacoes estao divergindo! Algo esta errado! Verifique fort.{14, 15, 16, 17}!"
    STOP
  endif
  matriz_temporaria(i) = temp_soma
  temp_soma = 0.d0
enddo

!if ( nsites /= 0.d0 ) then 
!matriz_temporaria(nqdots) = real(rho_matrix(rho_size, rho_size))
!endif 

open(nm_arquivo, file = filename, position = 'append')

!sem estado de recomb
write ( nm_arquivo,  '(60F12.5)', advance='no' ) t
write ( nm_arquivo,  '(60F12.5)', advance = 'no') (  (matriz_temporaria(i)),  i = 1, nqdots )
write ( nm_arquivo, '(60F12.5)' ) sum(matriz_temporaria(:)) 

close(nm_arquivo)

return
DEALLOCATE(matriz_temporaria)
end subroutine printa_resultado




! ---------------- AS DUAS SUBROTINAS CALCULAM O TRACO PARCIAL DE RHO ---------
SUBROUTINE C_PR_PT_B(N,K,Matr_input,Matr_output)
!C     C_PR_PT_A.f :: it take as input the 2 INTEGER numbers N and K and a
!C                 (N*K)x(N*K) COMPLEX matrix M and return as output the KxK
!C                 COMPLEX matrix "PARTIAL TRACE over A of M"
!C
implicit none

INTEGER N,K,emme,mu,nu
COMPLEX*16 Matr_input(N*K,N*K), Matr_NK(N,K,N,K), Matr_output(K,K)

Matr_NK=RESHAPE(Matr_input,(/N,K,N,K/)) !),(/0,0/),(/2,1,4,3/))

Do 10 nu=1,K
Do 10 mu=1,K
Matr_output(mu,nu) = 0.0d0
Do 10 emme=1,N
10 Matr_output(mu,nu) = Matr_output(mu,nu) + Matr_NK(emme,mu,emme,nu)
RETURN
END SUBROUTINE C_PR_PT_B


SUBROUTINE C_PR_PT_A(N,K,Matr_input,Matr_output)

!C     C_PR_PT_B.f :: it take as input the 2 INTEGER numbers N and K and a
!C                 (N*K)x(N*K) COMPLEX matrix M and return as output the NxN
!C                 COMPLEX matrix "PARTIAL TRACE over B of M"
implicit none

INTEGER N,K,emme,enne,mu
COMPLEX*16 Matr_input(N*K,N*K), Matr_NK(N,K,N,K), Matr_output(N,N)

 Matr_NK=RESHAPE(Matr_input,(/N,K,N,K/) )

Do 10 enne=1,N
Do 10 emme=1,N
Matr_output(emme,enne) = 0.0
Do 10 mu=1,K
10  Matr_output(emme,enne) = Matr_output(emme,enne) + Matr_NK(emme,mu,enne,mu)
RETURN
END SUBROUTINE C_PR_PT_A
!------------------------------------------------------------------------------

!funcao para calcular a derivada de um vetor
subroutine fderiv(dims, x_vector, y_vector, deriv)
implicit none
integer, intent(in) :: dims
real*8, dimension(dims), intent(in) :: x_vector, y_vector
real*8, dimension(dims), intent(out) :: deriv
integer :: i, j
real*8, dimension(dims-1) :: delx

delx = 0.d0
deriv = 0.d0


do i = 2, dims-1
   delx(i) =  x_vector(i) - x_vector(i-1)
   deriv(i) = (y_vector(i+1) - y_vector(i-1)) / (2.d0 * delx(i) )
enddo

deriv(1) = deriv(2)
deriv(dims) = deriv(dims-1)


return

end subroutine fderiv


subroutine print_mat2(aa, nn, mm)
implicit none
integer, intent(in) :: nn, mm
real*8, dimension(nn, mm), intent(in) :: aa
integer :: i, j
do, i=1,mm
    write(*,'(100g12.4)') ( aa(i,j), j=1,nn )
enddo

end subroutine print_mat2


SUBROUTINE tensor_product(A,B,AB)
Implicit none
!AB = Kronecker product of A and B, both two-dimensional arrays.
!Considers the arrays to be addressed as A(row,column), despite any storage order arrangements.        .
!Creating array AB to fit here, adjusting the caller's array AB, may not work on some compilers.
real*8 A(:,:),B(:,:) !Two-dimensional arrays, lower bound one.
real*8, ALLOCATABLE:: AB(:,:) !To be created to fit.
INTEGER R,RA,RB,C,CA,CB,I, J !Assistants.
          RA = UBOUND(A,DIM = 1) !Ascertain the upper bounds of the incoming arrays.
          CA = UBOUND(A,DIM = 2) !Their lower bounds will be deemed one,
          RB = UBOUND(B,DIM = 1) !And the upper bound as reported will correspond.
          CB = UBOUND(B,DIM = 2) !UBOUND(A) would give an array of two values, RA and CA, more for higher dimensionality.
          WRITE (6,1) "A",RA,CA,"B",RB,CB,"A.k.B",RA*RB,CA*CB !Announce.
    1     FORMAT (3(A," is ",I0,"x",I0,1X)) !Three sets of sizes.
          IF (ALLOCATED(AB)) DEALLOCATE(AB) !Discard any lingering storage.
          ALLOCATE (AB(RA*RB,CA*CB)) !Obtain the exact desired size.
          R = 0  !Syncopation: start the row offset.
          DO I = 1,RA !Step down the rows of A.
            C = 0 !For each row, start the column offset.
            DO J = 1,CA !Step along the columns of A.
              AB(R + 1:R + RB,C + 1:C + CB) = A(I,J)*B !Place a block of B values.
              C = C + CB !Advance a block of columns.
            END DO !On to the next column of A.
            R = R + RB !Advance a block of rows.
          END DO !On to the next row of A.
END SUBROUTINE tensor_product !No tests for bad parameters, or lack of storage...






!funcao para fazer a integral numerica de um vetor
!===================================
 function sumtrap(i1,i2,eixox,eixoy)
!===================================
integer , intent(in) :: i1 , i2
real*8  , intent(in) :: eixox(:)
real*8  , intent(in) :: eixoy(:)

real*8  :: sumtrap

!------------------------------------------------------------------------------
! CALCULA A INTEGRAL DA FUNCAO Y(I) PELO METODO DO TRAPEZIO COM PASSO VARIAVEL
!------------------------------------------------------------------------------

sumtrap  = sum( (eixox(i1+1:i2)-eixox(i1:i2-1)) * (eixoy(i1+1:i2)+eixoy(i1:i2-1)) ) / 2.0d0

end function sumtrap


subroutine printaletters2(nomearquivo, nmfile, matrizsize, nmlines, nmcol, matriz)
implicit none
character*6, INTENT(IN) :: nomearquivo
integer, intent(in) :: nmfile, matrizsize, nmlines, nmcol
real*8, intent(in), dimension(matrizsize, matrizsize) :: matriz


open(file = nomearquivo, status = "replace", unit = nmfile)
do j = 1, nmcol
  do i = 1, nmlines
    write(nmfile, 13, advance = "no") matriz(i, j)
  enddo
  write(nmfile, 13, advance = "yes")
enddo

close(nmfile)


!13 format (8F6.2)
!!13 format (12F9.5)
13 format (10F8.3)
return
end subroutine printaletters2




end module functions_m
