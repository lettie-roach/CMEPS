module med_merge_mod

  !-----------------------------------------------------------------------------
  ! Performs merges from source field bundles to destination field bundle
  !-----------------------------------------------------------------------------

  use med_constants_mod     , only : R8
  use med_constants_mod     , only : dbug_flag         => med_constants_dbug_flag
  use med_constants_mod     , only : spval_init        => med_constants_spval_init
  use med_constants_mod     , only : spval             => med_constants_spval
  use med_constants_mod     , only : czero             => med_constants_czero
  use med_constants_mod     , only : CL
  use shr_nuopc_utils_mod   , only : ChkErr            => shr_nuopc_utils_ChkErr
  use shr_nuopc_methods_mod , only : FB_FldChk         => shr_nuopc_methods_FB_FldChk
  use shr_nuopc_methods_mod , only : FB_GetNameN       => shr_nuopc_methods_FB_GetNameN
  use shr_nuopc_methods_mod , only : FB_Reset          => shr_nuopc_methods_FB_reset
  use shr_nuopc_methods_mod , only : FB_GetFldPtr      => shr_nuopc_methods_FB_GetFldPtr
  use shr_nuopc_methods_mod , only : FieldPtr_Compare  => shr_nuopc_methods_FieldPtr_Compare
  use med_internalstate_mod , only : logunit

  implicit none
  private

  public  :: med_merge_auto
  public  :: med_merge_field

  interface med_merge_field ; module procedure &
       med_merge_field_1D, &
       med_merge_field_2D
  end interface

  private :: med_merge_auto_field

  character(*),parameter :: u_FILE_u = &
       __FILE__

!===============================================================================
contains
!===============================================================================

  subroutine med_merge_auto(compout_name, FBOut, FBfrac, FBImp, fldListTo, FBMed1, FBMed2, rc)

    use ESMF                  , only : ESMF_FieldBundle
    use ESMF                  , only : ESMF_FieldBundleIsCreated, ESMF_FieldBundleGet
    use ESMF                  , only : ESMF_SUCCESS, ESMF_FAILURE, ESMF_LogWrite, ESMF_LogMsg_Info
    use ESMF                  , only : ESMF_LogSetError, ESMF_RC_OBJ_NOT_CREATED
    use med_constants_mod     , only : CL, CX, CS
    use esmFlds               , only : compmed, compname
    use esmFlds               , only : shr_nuopc_fldList_type
    use esmFlds               , only : shr_nuopc_fldList_GetNumFlds
    use esmFlds               , only : shr_nuopc_fldList_GetFldInfo
    use perf_mod              , only : t_startf, t_stopf
    use shr_nuopc_methods_mod , only : FB_Field_diagnose => shr_nuopc_methods_FB_Field_diagnose  !HK
    ! ----------------------------------------------
    ! Auto merge based on fldListTo info
    ! ----------------------------------------------

    ! input/output variables
    character(len=*)             , intent(in)            :: compout_name ! component name for FBOut
    type(ESMF_FieldBundle)       , intent(inout)         :: FBOut        ! Merged output field bundle
    type(ESMF_FieldBundle)       , intent(inout)         :: FBfrac       ! Fraction data for FBOut
    type(ESMF_FieldBundle)       , intent(in)            :: FBImp(:)     ! Array of field bundles each mapping to the FBOut mesh
    type(shr_nuopc_fldList_type) , intent(in)            :: fldListTo    ! Information for merging
    type(ESMF_FieldBundle)       , intent(in) , optional :: FBMed1       ! mediator field bundle
    type(ESMF_FieldBundle)       , intent(in) , optional :: FBMed2       ! mediator field bundle
    integer                      , intent(out)           :: rc

    ! local variables
    integer       :: cnt
    integer       :: n,nf,nm,compsrc
    character(CX) :: fldname, stdname
    character(CX) :: merge_fields
    character(CX) :: merge_field
    character(CS) :: merge_type
    character(CS) :: merge_fracname
    integer       :: dbrc
    character(len=*),parameter :: subname=' (module_med_merge_mod: med_merge_auto)'
    !---------------------------------------
    call t_startf('MED:'//subname)

    call ESMF_LogWrite(trim(subname)//": called", ESMF_LOGMSG_INFO, rc=dbrc)
    rc = ESMF_SUCCESS

    call FB_reset(FBOut, value=czero, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return

    ! Want to loop over all of the fields in FBout here - and find the corresponding index in fldListTo(compxxx)
    ! for that field name - then call the corresponding merge routine below appropriately

    call ESMF_FieldBundleGet(FBOut, fieldCount=cnt, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return


    ! Loop over all fields in field bundle FBOut
    do n = 1,cnt

       ! Get the nth field name in FBexp
       call FB_getNameN(FBOut, n, fldname, rc)
       if (ChkErr(rc,__LINE__,u_FILE_u)) return

       ! Loop over the field in fldListTo
       do nf = 1,shr_nuopc_fldList_GetNumFlds(fldListTo)

          ! Determine if if there is a match of the fldList field name with the FBOut field name
          call shr_nuopc_fldList_GetFldInfo(fldListTo, nf, stdname)

          if (trim(stdname) == trim(fldname)) then

             ! Loop over all possible source components in the merging arrays returned from the above call
             ! If the merge field name from the source components is not set, then simply go to the next component
             do compsrc = 1,size(FBImp)

                ! Determine the merge information for the import field
                call shr_nuopc_fldList_GetFldInfo(fldListTo, nf, compsrc, merge_fields, merge_type, merge_fracname)

                ! If merge_field is a colon delimited string then cycle through every field - otherwise by default nm
                ! will only equal 1
                do nm = 1,merge_listGetNum(merge_fields)

                   call merge_listGetName(merge_fields, nm, merge_field, rc)
                   if (ChkErr(rc,__LINE__,u_FILE_u)) return
                   if (merge_type /= 'unset' .and. merge_field /= 'unset') then

                      ! Perform merge
                      if (compsrc == compmed) then

                         if (present(FBMed1) .and. present(FBMed2)) then
                            if (.not. ESMF_FieldBundleIsCreated(FBMed1)) then
                               call ESMF_LogSetError(ESMF_RC_OBJ_NOT_CREATED,  &
                                    msg="Field bundle FBMed1 not created.", &
                                    line=__LINE__, file=u_FILE_u, rcToReturn=rc)
                               return
                            endif
                            if (.not. ESMF_FieldBundleIsCreated(FBMed2)) then
                               call ESMF_LogSetError(ESMF_RC_OBJ_NOT_CREATED,  &
                                    msg="Field bundle FBMed2 not created.", &
                                    line=__LINE__, file=u_FILE_u, rcToReturn=rc)
                               return
                            endif
                            if (FB_FldChk(FBMed1, trim(merge_field), rc=rc)) then
call FB_Field_diagnose(FBMed1, trim(merge_field),'FBMed1 taco', rc)
                               call med_merge_auto_field(trim(merge_type), &
                                    FBOut, fldname, FB=FBMed1, FBFld=merge_field, FBw=FBfrac, fldw=trim(merge_fracname), rc=rc)
                               if (ChkErr(rc,__LINE__,u_FILE_u)) return

                            else if (FB_FldChk(FBMed2, trim(merge_field), rc=rc)) then
call FB_Field_diagnose(FBMed2, trim(merge_field),'FBMed2 taco', rc)
                               call med_merge_auto_field(trim(merge_type), &
                                    FBOut, fldname, FB=FBMed2, FBFld=merge_field, FBw=FBfrac, fldw=trim(merge_fracname), rc=rc)
                               if (ChkErr(rc,__LINE__,u_FILE_u)) return

                            else
                               call ESMF_LogWrite(trim(subname)//": ERROR merge_field = "//trim(merge_field)//" not found", &
                                    ESMF_LOGMSG_INFO, rc=rc)
                               rc = ESMF_FAILURE
                               if (ChkErr(rc,__LINE__,u_FILE_u)) return
                            end if

                         elseif (present(FBMed1)) then
                            if (.not. ESMF_FieldBundleIsCreated(FBMed1)) then
                               call ESMF_LogSetError(ESMF_RC_OBJ_NOT_CREATED,  &
                                    msg="Field bundle FBMed1 not created.", &
                                    line=__LINE__, file=u_FILE_u, rcToReturn=rc)
                               return
                            endif
                            if (FB_FldChk(FBMed1, trim(merge_field), rc=rc)) then
call FB_Field_diagnose(FBMed1, trim(merge_field),'FBMed1 second taco', rc)
                               call med_merge_auto_field(trim(merge_type), &
                                    FBOut, fldname, FB=FBMed1, FBFld=merge_field, FBw=FBfrac, fldw=trim(merge_fracname), rc=rc)
                               if (ChkErr(rc,__LINE__,u_FILE_u)) return

                            else
                               call ESMF_LogWrite(trim(subname)//": ERROR merge_field = "//trim(merge_field)//"not found", &
                                    ESMF_LOGMSG_INFO, rc=rc)
                               rc = ESMF_FAILURE
                               if (ChkErr(rc,__LINE__,u_FILE_u)) return
                            end if
                         end if

                      else if (ESMF_FieldBundleIsCreated(FBImp(compsrc), rc=rc)) then
                         if (FB_FldChk(FBImp(compsrc), trim(merge_field), rc=rc)) then
!HK wave_elevation_spectrum is 1D here
call FB_Field_diagnose(FBImp(compsrc), trim(merge_field),'FBImp taco', rc)
                            call med_merge_auto_field(trim(merge_type), &
                                 FBOut, fldname, FB=FBImp(compsrc), FBFld=merge_field, &
                                 FBw=FBfrac, fldw=trim(merge_fracname), rc=rc)
                            if (ChkErr(rc,__LINE__,u_FILE_u)) return
                         end if

                      end if ! end of single merge

                   end if ! end of check of merge_type and merge_field not unset
                end do ! end of nmerges loop
             end do  ! end of compsrc loop
          end if ! end of check if stdname and fldname are the same
       end do ! end of loop over fldsListTo
    end do ! end of loop over fields in FBOut

    !---------------------------------------
    !--- clean up
    !---------------------------------------

    call ESMF_LogWrite(trim(subname)//": done", ESMF_LOGMSG_INFO, rc=dbrc)
    call t_stopf('MED:'//subname)

  end subroutine med_merge_auto

  !===============================================================================

  subroutine med_merge_auto_field(merge_type, FBout, FBoutfld, FB, FBfld, FBw, fldw, rc)

    use ESMF                  , only : ESMF_SUCCESS, ESMF_FAILURE, ESMF_LogMsg_Error
    use ESMF                  , only : ESMF_LogWrite, ESMF_LogMsg_Info
    use ESMF                  , only : ESMF_FieldBundle, ESMF_FieldBundleGet
    use ESMF                  , only : ESMF_FieldGet, ESMF_Field
 use shr_nuopc_methods_mod , only : FB_Field_diagnose => shr_nuopc_methods_FB_Field_diagnose  !HK
 use shr_nuopc_methods_mod , only : Field_diagnose    => shr_nuopc_methods_Field_diagnose !HK

    ! input/output variables
    character(len=*)      ,intent(in)    :: merge_type
    type(ESMF_FieldBundle),intent(inout) :: FBout
    character(len=*)      ,intent(in)    :: FBoutfld
    type(ESMF_FieldBundle),intent(in)    :: FB
    character(len=*)      ,intent(in)    :: FBfld
    type(ESMF_FieldBundle),intent(inout) :: FBw     ! field bundle with weights
    character(len=*)      ,intent(in)    :: fldw    ! name of weight field to use in FBw
    integer               ,intent(out)   :: rc

    ! local variables
    integer           :: n
    type(ESMF_Field)  :: lfield
    real(R8), pointer :: dp1 (:), dp2(:,:)         ! output pointers to 1d and 2d fields
    real(R8), pointer :: dpf1(:), dpf2(:,:)        ! intput pointers to 1d and 2d fields
    real(R8), pointer :: dpw1(:)                   ! weight pointer
    integer           :: lrank                     ! rank of array
    integer           :: ungriddedUBound_output(1) ! currently the size must equal 1 for rank 2 fieldds
    integer           :: ungriddedUBound_input(1)  ! currently the size must equal 1 for rank 2 fieldds
    integer           :: gridToFieldMap_output(1)  ! currently the size must equal 1 for rank 2 fieldds
    integer           :: gridToFieldMap_input(1)   ! currently the size must equal 1 for rank 2 fieldds
    character(len=CL) :: errmsg
    character(len=*),parameter :: subname=' (med_merge_mod: med_merge)'
    !---------------------------------------

    rc = ESMF_SUCCESS

    !-------------------------
    ! Error checks
    !-------------------------

    if (merge_type == 'copy_with_weights' .or. merge_type == 'merge') then
       if (trim(fldw) == 'unset') then
          call ESMF_LogWrite(trim(subname)//": error required merge_fracname is not set", &
               ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u)
          rc = ESMF_FAILURE
          return
       end if
       if (.not. FB_FldChk(FBw, trim(fldw), rc=rc)) then
          call ESMF_LogWrite(trim(subname)//": error "//trim(fldw)//"is not in FBw", &
               ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u)
          rc = ESMF_FAILURE
          return
       end if
    end if

    !-------------------------
    ! Get appropriate field pointers
    !-------------------------

call FB_Field_diagnose(FB, trim(FBfld),'input taco', rc)
call FB_Field_diagnose(FBout, trim(FBoutfld),'output taco', rc)

    ! Get field pointer to output field
    call ESMF_FieldBundleGet(FBout, fieldName=trim(FBoutfld), field=lfield, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    call ESMF_FieldGet(lfield, rank=lrank, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    if (lrank == 1) then
       call ESMF_FieldGet(lfield, farrayPtr=dp1, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
    elsE if (lrank == 2) then
       ! wave_elevation_spectrum is rank 2 for outputfield
       call ESMF_FieldGet(lfield, ungriddedUBound=ungriddedUBound_output, &
            gridToFieldMap=gridToFieldMap_output, rc=rc)
       print*, 'hello lrank = 2, FBout ', trim(FBoutfld)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
       call ESMF_FieldGet(lfield, farrayPtr=dp2, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
    end if

    ! Get field pointer to input field used in the merge
    call ESMF_FieldBundleGet(FB, fieldName=trim(FBfld), field=lfield, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    call ESMF_FieldGet(lfield, rank=lrank, rc=rc)
    if (chkerr(rc,__LINE__,u_FILE_u)) return
    if (lrank == 1) then
       !HK bug: wave_elevation_spectrum is rank 1 for inputfield
       print*, 'hello lrank = 1, FBfld ', trim(FBfld)
       call ESMF_FieldGet(lfield, farrayPtr=dpf1, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
    else if (lrank == 2) then
       print*, 'hello lrank = 2, FBfld ', trim(FBfld)
       call ESMF_FieldGet(lfield, ungriddedUBound=ungriddedUBound_input, &
            gridToFieldMap=gridToFieldMap_input, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
       call ESMF_FieldGet(lfield, farrayPtr=dpf2, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
    end if

    ! error checks
    if (lrank == 2) then
       if (ungriddedUBound_output(1) /= ungriddedUBound_input(1)) then
          write(errmsg,*) trim(subname),"ungriddedUBound_input (",ungriddedUBound_input(1),&
               ") not equal to ungriddedUBound_output (",ungriddedUBound_output(1),")"
          call ESMF_LogWrite(errmsg, ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       else if (gridToFieldMap_input(1) /= gridToFieldMap_output(1)) then
          write(errmsg,*) trim(subname),"gridtofieldmap_input (",gridtofieldmap_input(1),&
               ") not equal to gridtofieldmap_output (",gridtofieldmap_output(1),")"
          call ESMF_LogWrite(errmsg, ESMF_LOGMSG_ERROR)
          rc = ESMF_FAILURE
          return
       end if
    endif
    ! Get pointer to weights that weights are only rank 1
    if (merge_type == 'copy_with_weights' .or. merge_type == 'merge' .or. merge_type == 'sum_with_weights') then
       call ESMF_FieldBundleGet(FBw, fieldName=trim(fldw), field=lfield, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
       call ESMF_FieldGet(lfield, farrayPtr=dpw1, rc=rc)
       if (chkerr(rc,__LINE__,u_FILE_u)) return
    endif

    ! Do supported merges
    if (trim(merge_type)  == 'copy') then
       if (lrank == 1) then
          dp1(:) = dpf1(:)
       else
          dp2(:,:) = dpf2(:,:)
       endif
    else if (trim(merge_type)  == 'copy_with_weights') then
       if (lrank == 1) then
          dp1(:) = dpf1(:)*dpw1(:)
       else
          do n = 1,ungriddedUBound_input(1)
             if (gridToFieldMap_input(1) == 1) then
                dp2(:,n) = dpf2(:,n)*dpw1(:)
             else if (gridToFieldMap_input(1) == 2) then
                dp2(n,:) = dpf2(n,:)*dpw1(:)
             end if
          end do
       endif
    else if (trim(merge_type)  == 'merge' .or. trim(merge_type) == 'sum_with_weights') then
       if (lrank == 1) then
          dp1(:) = dp1(:) + dpf1(:)*dpw1(:)
       else
          do n = 1,ungriddedUBound_input(1)
             if (gridToFieldMap_input(1) == 1) then
                dp2(:,n) = dp2(:,n) + dpf2(:,n)*dpw1(:)
             else if (gridToFieldMap_input(1) == 2) then
                dp2(n,:) = dp2(n,:) + dpf2(n,:)*dpw1(:)
             end if
          end do
       endif
    else if (trim(merge_type) == 'sum') then
       if (lrank == 1) then
          dp1(:) = dp1(:) + dpf1(:)
       else
          dp2(:,:) = dp2(:,:) + dpf2(:,:)
       endif
    else
       call ESMF_LogWrite(trim(subname)//": merge type "//trim(merge_type)//" not supported", &
            ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u)
       rc = ESMF_FAILURE
       return
    end if

  end subroutine med_merge_auto_field

  !===============================================================================

  subroutine med_merge_field_1D(FBout, fnameout, &
                                FBinA, fnameA, wgtA, &
                                FBinB, fnameB, wgtB, &
                                FBinC, fnameC, wgtC, &
                                FBinD, fnameD, wgtD, &
                                FBinE, fnameE, wgtE, rc)

    use ESMF , only : ESMF_FieldBundle, ESMF_LogWrite
    use ESMF , only : ESMF_SUCCESS, ESMF_FAILURE, ESMF_LOGMSG_ERROR
    use ESMF , only : ESMF_LOGMSG_WARNING, ESMF_LOGMSG_INFO

    ! ----------------------------------------------
    ! Supports up to a five way merge
    ! ----------------------------------------------

    ! input/output variabes
    type(ESMF_FieldBundle) , intent(inout)                 :: FBout
    character(len=*)       , intent(in)                    :: fnameout
    type(ESMF_FieldBundle) , intent(in)                    :: FBinA
    character(len=*)       , intent(in)                    :: fnameA
    real(R8)               , intent(in), pointer           :: wgtA(:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinB
    character(len=*)       , intent(in), optional          :: fnameB
    real(R8)               , intent(in), optional, pointer :: wgtB(:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinC
    character(len=*)       , intent(in), optional          :: fnameC
    real(R8)               , intent(in), optional, pointer :: wgtC(:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinD
    character(len=*)       , intent(in), optional          :: fnameD
    real(R8)               , intent(in), optional, pointer :: wgtD(:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinE
    character(len=*)       , intent(in), optional          :: fnameE
    real(R8)               , intent(in), optional, pointer :: wgtE(:)
    integer                , intent(out)                   :: rc

    ! local variables
    real(R8), pointer          :: dataOut(:)
    real(R8), pointer          :: dataPtr(:)
    real(R8), pointer          :: wgt(:)
    integer                    :: lb1,ub1,i,j,n
    logical                    :: wgtfound, FBinfound
    integer                    :: dbrc
    character(len=*),parameter :: subname='(med_merge_fieldo_1d)'
    ! ----------------------------------------------

    if (dbug_flag > 10) then
       call ESMF_LogWrite(trim(subname)//": called", ESMF_LOGMSG_INFO, rc=dbrc)
    endif
    rc=ESMF_SUCCESS

    ! check each field has a fieldname passed in
    if ((present(FBinB) .and. .not.present(fnameB)) .or. &
        (present(FBinC) .and. .not.present(fnameC)) .or. &
        (present(FBinD) .and. .not.present(fnameD)) .or. &
        (present(FBinE) .and. .not.present(fnameE))) then

       call ESMF_LogWrite(trim(subname)//": ERROR fname not present with FBin", &
            ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u, rc=dbrc)
       rc = ESMF_FAILURE
       return
    endif

    if (.not. FB_FldChk(FBout, trim(fnameout), rc=rc)) then
       call ESMF_LogWrite(trim(subname)//": WARNING field not in FBout, skipping merge "//trim(fnameout), &
            ESMF_LOGMSG_WARNING, line=__LINE__, file=u_FILE_u, rc=dbrc)
       return
    endif

    call FB_GetFldPtr(FBout, trim(fnameout), fldptr1=dataOut, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    lb1 = lbound(dataOut,1)
    ub1 = ubound(dataOut,1)
    allocate(wgt(lb1:ub1))

    dataOut = czero

    ! check that each field passed in actually exists, if not DO NOT do any merge
    FBinfound = .true.
    if (present(FBinB)) then
       if (.not. FB_FldChk(FBinB, trim(fnameB), rc=rc)) FBinfound = .false.
    endif
    if (present(FBinC)) then
       if (.not. FB_FldChk(FBinC, trim(fnameC), rc=rc)) FBinfound = .false.
    endif
    if (present(FBinD)) then
       if (.not. FB_FldChk(FBinD, trim(fnameD), rc=rc)) FBinfound = .false.
    endif
    if (present(FBinE)) then
       if (.not. FB_FldChk(FBinE, trim(fnameE), rc=rc)) FBinfound = .false.
    endif
    if (.not. FBinfound) then
       call ESMF_LogWrite(trim(subname)//": WARNING field not found in FBin, skipping merge "//trim(fnameout), &
            ESMF_LOGMSG_WARNING, line=__LINE__, file=u_FILE_u, rc=dbrc)
       return
    endif

    ! n=1,5 represents adding A to E inputs if they exist
    do n = 1,5
       FBinfound = .false.
       wgtfound = .false.

       if (n == 1) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinA, trim(fnameA), fldptr1=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          wgtfound = .true.
          wgt => wgtA

       elseif (n == 2 .and. present(FBinB)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinB, trim(fnameB), fldptr1=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtB)) then
             wgtfound = .true.
             wgt => wgtB
          endif

       elseif (n == 3 .and. present(FBinC)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinC, trim(fnameC), fldptr1=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtC)) then
             wgtfound = .true.
             wgt => wgtC
          endif

       elseif (n == 4 .and. present(FBinD)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinD, trim(fnameD), fldptr1=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtD)) then
             wgtfound = .true.
             wgt => wgtD
          endif

       elseif (n == 5 .and. present(FBinE)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinE, trim(fnameE), fldptr1=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtE)) then
             wgtfound = .true.
             wgt => wgtE
          endif

       endif

       if (FBinfound) then
          if (.not.FieldPtr_Compare(dataPtr, dataOut, subname, rc)) then
             call ESMF_LogWrite(trim(subname)//": ERROR FBin wrong size", &
                  ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u, rc=dbrc)
             rc = ESMF_FAILURE
             return
          endif

          if (wgtfound) then
             if (.not.FieldPtr_Compare(dataPtr, wgt, subname, rc)) then
                call ESMF_LogWrite(trim(subname)//": ERROR wgt wrong size", &
                     ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u, rc=dbrc)
                rc = ESMF_FAILURE
                return
             endif
             do i = lb1,ub1
                dataOut(i) = dataOut(i) + dataPtr(i) * wgt(i)
             enddo
          else
             do i = lb1,ub1
                dataOut(i) = dataOut(i) + dataPtr(i)
             enddo
          endif  ! wgtfound

       endif  ! FBin found
    enddo  ! n

    if (dbug_flag > 10) then
       call ESMF_LogWrite(trim(subname)//": done", ESMF_LOGMSG_INFO, rc=dbrc)
    endif

  end subroutine med_merge_field_1D

  !===============================================================================

  subroutine med_merge_field_2D(FBout, fnameout,     &
                                FBinA, fnameA, wgtA, &
                                FBinB, fnameB, wgtB, &
                                FBinC, fnameC, wgtC, &
                                FBinD, fnameD, wgtD, &
                                FBinE, fnameE, wgtE, rc)

    use ESMF , only : ESMF_FieldBundle, ESMF_LogWrite
    use ESMF , only : ESMF_SUCCESS, ESMF_FAILURE, ESMF_LOGMSG_ERROR
    use ESMF , only : ESMF_LOGMSG_WARNING, ESMF_LOGMSG_INFO

    ! ----------------------------------------------
    ! Supports up to a five way merge
    ! ----------------------------------------------

    ! input/output arguments
    type(ESMF_FieldBundle) , intent(inout)                 :: FBout
    character(len=*)       , intent(in)                    :: fnameout
    type(ESMF_FieldBundle) , intent(in)                    :: FBinA
    character(len=*)       , intent(in)                    :: fnameA
    real(R8)               , intent(in), pointer           :: wgtA(:,:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinB
    character(len=*)       , intent(in), optional          :: fnameB
    real(R8)               , intent(in), optional, pointer :: wgtB(:,:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinC
    character(len=*)       , intent(in), optional          :: fnameC
    real(R8)               , intent(in), optional, pointer :: wgtC(:,:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinD
    character(len=*)       , intent(in), optional          :: fnameD
    real(R8)               , intent(in), optional, pointer :: wgtD(:,:)
    type(ESMF_FieldBundle) , intent(in), optional          :: FBinE
    character(len=*)       , intent(in), optional          :: fnameE
    real(R8)               , intent(in), optional, pointer :: wgtE(:,:)
    integer                , intent(out)                   :: rc

    ! local variables
    real(R8), pointer          :: dataOut(:,:)
    real(R8), pointer          :: dataPtr(:,:)
    real(R8), pointer          :: wgt(:,:)
    integer                    :: lb1,ub1,lb2,ub2,i,j,n
    logical                    :: wgtfound, FBinfound
    integer                    :: dbrc
    character(len=*),parameter :: subname='(med_merge_field_2d)'
    ! ----------------------------------------------

    if (dbug_flag > 10) then
       call ESMF_LogWrite(trim(subname)//": called", ESMF_LOGMSG_INFO, rc=dbrc)
    endif
    rc=ESMF_SUCCESS

    if (.not. FB_FldChk(FBout, trim(fnameout), rc=rc)) then
       call ESMF_LogWrite(trim(subname)//": WARNING field not in FBout, skipping merge "//&
            trim(fnameout), ESMF_LOGMSG_WARNING, line=__LINE__, file=u_FILE_u, rc=dbrc)
       return
    endif

    call FB_GetFldPtr(FBout, trim(fnameout), fldptr2=dataOut, rc=rc)
    if (ChkErr(rc,__LINE__,u_FILE_u)) return
    lb1 = lbound(dataOut,1)
    ub1 = ubound(dataOut,1)
    lb2 = lbound(dataOut,2)
    ub2 = ubound(dataOut,2)
    allocate(wgt(lb1:ub1,lb2:ub2))

    dataOut = czero

    ! check each field has a fieldname passed in
    if ((present(FBinB) .and. .not.present(fnameB)) .or. &
        (present(FBinC) .and. .not.present(fnameC)) .or. &
        (present(FBinD) .and. .not.present(fnameD)) .or. &
        (present(FBinE) .and. .not.present(fnameE))) then
       call ESMF_LogWrite(trim(subname)//": ERROR fname not present with FBin", &
            ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u, rc=dbrc)
       rc = ESMF_FAILURE
       return
    endif

    ! check that each field passed in actually exists, if not DO NOT do any merge
    FBinfound = .true.
    if (present(FBinB)) then
       if (.not. FB_FldChk(FBinB, trim(fnameB), rc=rc)) FBinfound = .false.
    endif
    if (present(FBinC)) then
       if (.not. FB_FldChk(FBinC, trim(fnameC), rc=rc)) FBinfound = .false.
    endif
    if (present(FBinD)) then
       if (.not. FB_FldChk(FBinD, trim(fnameD), rc=rc)) FBinfound = .false.
    endif
    if (present(FBinE)) then
       if (.not. FB_FldChk(FBinE, trim(fnameE), rc=rc)) FBinfound = .false.
    endif
    if (.not. FBinfound) then
       call ESMF_LogWrite(trim(subname)//": WARNING field not found in FBin, skipping merge "//trim(fnameout), &
            ESMF_LOGMSG_WARNING, line=__LINE__, file=u_FILE_u, rc=dbrc)
       return
    endif

    ! n=1,5 represents adding A to E inputs if they exist
    do n = 1,5
       FBinfound = .false.
       wgtfound = .false.

       if (n == 1) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinA, trim(fnameA), fldptr2=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          wgtfound = .true.
          wgt => wgtA

       elseif (n == 2 .and. present(FBinB)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinB, trim(fnameB), fldptr2=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtB)) then
             wgtfound = .true.
             wgt => wgtB
          endif

       elseif (n == 3 .and. present(FBinC)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinC, trim(fnameC), fldptr2=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtC)) then
             wgtfound = .true.
             wgt => wgtC
          endif

       elseif (n == 4 .and. present(FBinD)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinD, trim(fnameD), fldptr2=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtD)) then
             wgtfound = .true.
             wgt => wgtD
          endif

       elseif (n == 5 .and. present(FBinE)) then
          FBinfound = .true.
          call FB_GetFldPtr(FBinE, trim(fnameE), fldptr2=dataPtr, rc=rc)
          if (ChkErr(rc,__LINE__,u_FILE_u)) return
          if (present(wgtE)) then
             wgtfound = .true.
             wgt => wgtE
          endif

       endif

       if (FBinfound) then
          if (.not.FieldPtr_Compare(dataPtr, dataOut, subname, rc)) then
             call ESMF_LogWrite(trim(subname)//": ERROR FBin wrong size", &
                  ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u, rc=dbrc)
             rc = ESMF_FAILURE
             return
          endif

          if (wgtfound) then
             if (.not. FieldPtr_Compare(dataPtr, wgt, subname, rc)) then
                call ESMF_LogWrite(trim(subname)//": ERROR wgt wrong size", &
                     ESMF_LOGMSG_ERROR, line=__LINE__, file=u_FILE_u, rc=dbrc)
                rc = ESMF_FAILURE
                return
             endif
             do j = lb2,ub2
                do i = lb1,ub1
                   dataOut(i,j) = dataOut(i,j) + dataPtr(i,j) * wgt(i,j)
                enddo
             enddo
          else
             do j = lb2,ub2
                do i = lb1,ub1
                   dataOut(i,j) = dataOut(i,j) + dataPtr(i,j)
                enddo
             enddo
          endif  ! wgtfound

       endif  ! FBin found
    enddo  ! n

    if (dbug_flag > 10) then
       call ESMF_LogWrite(trim(subname)//": done", ESMF_LOGMSG_INFO, rc=dbrc)
    endif

  end subroutine med_merge_field_2D

  !===============================================================================

  integer function merge_listGetNum(str)

    !  return number of fields in a colon delimited string list

    ! input/output variables
    character(*),intent(in) :: str   ! string to search

    ! local variables
    integer          :: n
    integer          :: count          ! counts occurances of char
    character(len=1) :: listDel  = ":" ! note single exec implications
    !---------------------------------------

    merge_listGetNum = 0
    if (len_trim(str) > 0) then
       count = 0
       do n = 1, len_trim(str)
          if (str(n:n) == listDel) count = count + 1
       end do
       merge_listGetNum = count + 1
    endif

  end function merge_listGetNum

  !===============================================================================

  subroutine merge_listGetName(list, k, name, rc)

    ! Get name of k-th field in colon deliminted list

    use ESMF, only : ESMF_SUCCESS, ESMF_FAILURE, ESMF_LogWrite, ESMF_LOGMSG_INFO

    ! input/output variables
    character(len=*)  ,intent(in)  :: list    ! list/string
    integer           ,intent(in)  :: k       ! index of field
    character(len=*)  ,intent(out) :: name    ! k-th name in list
    integer, optional ,intent(out) :: rc      ! return code

    ! local variables
    integer          :: i,n   ! generic indecies
    integer          :: kFlds ! number of fields in list
    integer          :: i0,i1 ! name = list(i0:i1)
    integer          :: nChar
    logical          :: valid_list
    character(len=1) :: listDel  = ':'
    character(len=2) :: listDel2 = '::'
    !---------------------------------------

    rc = ESMF_SUCCESS

    ! check that this is a valid list
    valid_list = .true.
    nChar = len_trim(list)
    if (nChar < 1) then                           ! list is an empty string
       valid_list = .false.
    else if (    list(1:1)     == listDel  ) then ! first char is delimiter
       valid_list = .false.
    else if (list(nChar:nChar) == listDel  ) then ! last  char is delimiter
       valid_list = .false.
    else if (index(trim(list)," " )     > 0) then ! white-space in a field name
       valid_list = .false.
    else if (index(trim(list),listDel2) > 0) then ! found zero length field
       valid_list = .false.
    end if
    if (.not. valid_list) then
       write(logunit,*) "ERROR: invalid list = ",trim(list)
       call ESMF_LogWrite("ERROR: invalid list = "//trim(list), ESMF_LOGMSG_INFO, rc=rc)
       rc = ESMF_FAILURE
       return
    end if

    !--- check that this is a valid index ---
    kFlds = merge_listGetNum(list)
    if (k<1 .or. kFlds<k) then
       write(logunit,*) "ERROR: invalid index = ",k
       write(logunit,*) "ERROR:          list = ",trim(list)
       call ESMF_LogWrite("ERROR: invalid index = "//trim(list), ESMF_LOGMSG_INFO, rc=rc)
       rc = ESMF_FAILURE
       return
    end if

    ! start with whole list, then remove fields before and after desired field ---
    i0 = 1
    i1 = len_trim(list)

    ! remove field names before desired field
    do n=2,k
       i = index(list(i0:i1),listDel)
       i0 = i0 + i
    end do

    ! remove field names after desired field
    if ( k < kFlds ) then
       i = index(list(i0:i1),listDel)
       i1 = i0 + i - 2
    end if

    ! copy result into output variable
    name = list(i0:i1)//"   "

  end subroutine merge_listGetName

end module med_merge_mod
