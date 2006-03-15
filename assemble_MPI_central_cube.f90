!=====================================================================
!
!          S p e c f e m 3 D  G l o b e  V e r s i o n  3 . 5
!          --------------------------------------------------
!
!                 Dimitri Komatitsch and Jeroen Tromp
!    Seismological Laboratory - California Institute of Technology
!        (c) California Institute of Technology July 2004
!
!    A signed non-commercial agreement is required to use this program.
!   Please check http://www.gps.caltech.edu/research/jtromp for details.
!           Free for non-commercial academic research ONLY.
!      This program is distributed WITHOUT ANY WARRANTY whatsoever.
!      Do not redistribute this program without written permission.
!
!=====================================================================

subroutine assemble_MPI_central_cube(ichunk,nb_msgs_theor_in_cube, sender_from_slices_to_cube, &
  npoin2D_cube_from_slices, buffer_all_cube_from_slices, buffer_slices, ibool_central_cube, &
  receiver_cube_from_slices, ibool_inner_core, idoubling_inner_core, NSPEC_INNER_CORE, &
  ibelm_bottom_inner_core, NSPEC2D_BOTTOM_INNER_CORE,NGLOB_INNER_CORE,vector_assemble, ndim_assemble)

  implicit none

 ! standard include of the MPI library
  include 'mpif.h'
  include 'constants.h'

! for matching with central cube in inner core
  integer ichunk, nb_msgs_theor_in_cube, npoin2D_cube_from_slices
  integer, dimension(nb_msgs_theor_in_cube) :: sender_from_slices_to_cube
  double precision, dimension(npoin2D_cube_from_slices,NDIM) :: buffer_slices
  double precision, dimension(nb_msgs_theor_in_cube,npoin2D_cube_from_slices,NDIM) :: buffer_all_cube_from_slices
  integer, dimension(nb_msgs_theor_in_cube,npoin2D_cube_from_slices):: ibool_central_cube
  integer receiver_cube_from_slices

! local to global mapping
  integer NSPEC_INNER_CORE,NSPEC2D_BOTTOM_INNER_CORE, NGLOB_INNER_CORE
  integer, dimension(NGLLX,NGLLY,NGLLZ,NSPEC_INNER_CORE) :: ibool_inner_core
  integer, dimension(NSPEC_INNER_CORE) :: idoubling_inner_core
  integer, dimension(NSPEC2D_BOTTOM_INNER_CORE) :: ibelm_bottom_inner_core

! vector
  integer ndim_assemble
  real(kind=CUSTOM_REAL), dimension(ndim_assemble,NGLOB_INNER_CORE) :: vector_assemble

  integer ipoin,idimension, ispec2D, ispec
  integer i,j,k
  integer isender,ireceiver,imsg

  real(kind=CUSTOM_REAL), dimension(NGLOB_INNER_CORE) :: array_central_cube

! MPI status of messages to be received
  integer msg_status(MPI_STATUS_SIZE), ier



!---
!---  now use buffers to assemble mass matrix with central cube once and for all
!---

! on chunk AB, receive all the messages from slices
  if(ichunk == CHUNK_AB) then

   do imsg = 1,nb_msgs_theor_in_cube

! receive buffers from slices
  isender = sender_from_slices_to_cube(imsg)
  call MPI_RECV(buffer_slices, &
              ndim_assemble*npoin2D_cube_from_slices,MPI_DOUBLE_PRECISION,isender, &
              itag,MPI_COMM_WORLD,msg_status,ier)

! copy buffer in 2D array for each slice
   buffer_all_cube_from_slices(imsg,:,1:ndim_assemble) = buffer_slices(:,1:ndim_assemble)

   enddo
   endif


! send info to central cube from all the slices except those in CHUNK_AB
  if(ichunk /= CHUNK_AB) then

! for bottom elements in contact with central cube from the slices side
    ipoin = 0
    do ispec2D = 1,NSPEC2D_BOTTOM_INNER_CORE

      ispec = ibelm_bottom_inner_core(ispec2D)

! only for DOFs exactly on surface of central cube (bottom of these elements)
      k = 1
      do j = 1,NGLLY
        do i = 1,NGLLX
          ipoin = ipoin + 1
          buffer_slices(ipoin,1:ndim_assemble) = dble(vector_assemble(1:ndim_assemble,ibool_inner_core(i,j,k,ispec)))
        enddo
      enddo
    enddo

! send buffer to central cube
    ireceiver = receiver_cube_from_slices
    call MPI_SEND(buffer_slices,ndim_assemble*npoin2D_cube_from_slices, &
              MPI_DOUBLE_PRECISION,ireceiver,itag,MPI_COMM_WORLD,ier)

 endif  ! end sending info to central cube

!--- now we need to assemble the contributions

  if(ichunk == CHUNK_AB) then

  do idimension = 1,ndim_assemble
! erase contributions to central cube array
   array_central_cube(:) = 0._CUSTOM_REAL

! use indirect addressing to store contributions only once
! distinguish between single and double precision for reals
   do imsg = 1,nb_msgs_theor_in_cube
   do ipoin = 1,npoin2D_cube_from_slices
     if(CUSTOM_REAL == SIZE_REAL) then
       array_central_cube(ibool_central_cube(imsg,ipoin)) = sngl(buffer_all_cube_from_slices(imsg,ipoin,idimension))
     else
       array_central_cube(ibool_central_cube(imsg,ipoin)) = buffer_all_cube_from_slices(imsg,ipoin,idimension)
     endif
   enddo
   enddo

! suppress degrees of freedom already assembled at top of cube on edges
  do ispec = 1,NSPEC_INNER_CORE
    if(idoubling_inner_core(ispec) == IFLAG_TOP_CENTRAL_CUBE) then
      k = NGLLZ
      do j = 1,NGLLY
        do i = 1,NGLLX
          array_central_cube(ibool_inner_core(i,j,k,ispec)) = 0._CUSTOM_REAL
        enddo
      enddo
    endif
  enddo

! assemble contributions
  vector_assemble(idimension,:) = vector_assemble(idimension,:) + array_central_cube(:)

! copy sum back
   do imsg = 1,nb_msgs_theor_in_cube
   do ipoin = 1,npoin2D_cube_from_slices
     buffer_all_cube_from_slices(imsg,ipoin,idimension) = vector_assemble(idimension,ibool_central_cube(imsg,ipoin))
   enddo
   enddo

   enddo

   endif


!----------

! receive info from central cube on all the slices except those in CHUNK_AB
  if(ichunk /= CHUNK_AB) then

! receive buffers from slices
  isender = receiver_cube_from_slices
  call MPI_RECV(buffer_slices, &
              ndim_assemble*npoin2D_cube_from_slices,MPI_DOUBLE_PRECISION,isender, &
              itag,MPI_COMM_WORLD,msg_status,ier)

! for bottom elements in contact with central cube from the slices side
    ipoin = 0
    do ispec2D = 1,NSPEC2D_BOTTOM_INNER_CORE

      ispec = ibelm_bottom_inner_core(ispec2D)

! only for DOFs exactly on surface of central cube (bottom of these elements)
      k = 1
      do j = 1,NGLLY
        do i = 1,NGLLX
          ipoin = ipoin + 1

! distinguish between single and double precision for reals
          if(CUSTOM_REAL == SIZE_REAL) then
            vector_assemble(1:ndim_assemble,ibool_inner_core(i,j,k,ispec)) = sngl(buffer_slices(ipoin,1:ndim_assemble))
          else
            vector_assemble(1:ndim_assemble,ibool_inner_core(i,j,k,ispec)) = buffer_slices(ipoin,1:ndim_assemble)
          endif

        enddo
      enddo
    enddo

 endif  ! end receiving info from central cube

!------- send info back from central cube to slices

! on chunk AB, send all the messages to slices
  if(ichunk == CHUNK_AB) then

   do imsg = 1,nb_msgs_theor_in_cube

! copy buffer in 2D array for each slice
   buffer_slices(:,1:ndim_assemble) = buffer_all_cube_from_slices(imsg,:,1:ndim_assemble)

! send buffers to slices
    ireceiver = sender_from_slices_to_cube(imsg)
    call MPI_SEND(buffer_slices,ndim_assemble*npoin2D_cube_from_slices, &
              MPI_DOUBLE_PRECISION,ireceiver,itag,MPI_COMM_WORLD,ier)

   enddo
   endif

end subroutine assemble_MPI_central_cube
