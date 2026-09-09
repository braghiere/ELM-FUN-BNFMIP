module CNFUNMod

!#include "shr_assert.h"
!--------------------------------------------------------------------
  !---
! ! DESCRIPTION
! ! The FUN model developed by Fisher et al. 2010 and
! ! end Brzostek et al. 2014. Coded by Mingjie Shi 2015.
! ! Coding logic and structure altered by Rosie Fisher. October 2015. 
! ! Critically, this removes the 'FUN-resistors' idea of Brzostek et
  !  al. 2014
! ! and replaces it with uptake that is proportional to the N/C
  !  exchange rate. 
! ! and adjusts the logic so that FUN does not depends upon the
  !  CLM4.0 'FPG' downregulation idea
! ! and instead it takes C spent on N uptake away from growth.
! ! The critical output of this code are sminn_to_plant_fun and
  !  npp_Nuptake, which are the N 
! ! available to the plant for growth, and the C spent on obtaining
  !  it. 
! ! Coding logic added in ELM with Phosphorus costs 
  ! by Renato Braghiere 2019.


  ! !USES:
  use shr_kind_mod        , only : r8 => shr_kind_r8
  use shr_log_mod         , only : errMsg => shr_log_errMsg
  use clm_varcon          , only : dzsoi_decomp
  use clm_varcon          , only : secspday, smallValue, fun_period 
  use clm_varcon          , only : tfrz, spval
  use clm_varctl          , only : use_c13, use_c14, use_nitrif_denitrif, spinup_state
  use clm_varctl          , only : use_funp
  use clm_varctl          , only : nyears_ad_carbon_only
  use abortutils          , only : endrun
  use decompMod           , only : bounds_type
  use subgridAveMod       , only : p2c
  use CanopyStateType     , only : canopystate_type
  use CNCarbonFluxType    , only : carbonflux_type
  use CNCarbonStateType   , only : carbonstate_type
  use CNNitrogenFluxType  , only : nitrogenflux_type
  use CNNitrogenStateType , only : nitrogenstate_type
  !!! add phosphorus
  use PhosphorusFluxType  , only : phosphorusflux_type
  use PhosphorusStateType , only : phosphorusstate_type
  use CNStateType         , only : cnstate_type
  use PhotosynthesisType  , only : photosyns_type
  use CropType            , only : crop_type
  use VegetationPropertiesType      , only : veg_vp
  use LandunitType        , only : lun_pp                
  use ColumnType          , only : col_pp
  use ColumnDataType      , only : col_ws
  use ColumnDataType      , only : col_cf, c13_col_cf, c14_col_cf
  use ColumnDataType      , only : col_ns, col_nf, col_ps, col_pf 
  use ColumnDataType      , only : col_es 
  use VegetationType      , only : veg_pp
  use VegetationDataType  , only : veg_cs, veg_ns, veg_nf, veg_ps, veg_pf
  use VegetationDataType  , only : veg_cf, c13_veg_cf, c14_veg_cf  
  use VegetationDataType  , only : veg_wf
  ! bgc interface & pflotran module switches
  use clm_varctl          , only : use_clm_interface,use_clm_bgc, use_pflotran, pf_cmode
  use clm_varctl          , only : nu_com
  use SoilStatetype       , only : soilstate_type
  use WaterStateType      , only : waterstate_type
  use clm_varctl          , only : NFIX_PTASE_plant

  ! used variables for FUN
  use SoilHydrologyType   , only : soilhydrology_type
  use TemperatureType     , only : temperature_type
  use WaterFluxType       , only : waterflux_type
  use perf_mod            , only : t_startf, t_stopf
  !
  !
  implicit none
  save
  private

! !PUBLIC MEMBER FUNCTIONS:
  public:: readParams            ! Read in parameters needed for FUN
  public:: CNFUNInit             ! FUN calculation initialization
  public:: CNFUN                 ! Run FUN
  
  type, private :: params_type
     real(r8) :: ndays_on        ! number of days to complete leaf onset
     real(r8) :: ndays_off       ! number of days to complete leaf offset
  end type params_type   
 
  !
  type(params_type), private :: params_inst  ! params_inst is
  !  populated in readParamsMod
  !
  !
  ! !PRIVATE DATA MEMBERS:
  real(r8) :: dt              ! decomp timestep (seconds)
  real(r8) :: ndays_on        ! number of days to complete onset
  real(r8) :: ndays_off       ! number of days to complete offset
  
  integer, private, parameter :: COST_METHOD = 2 !new way of doing the N uptake
  ! resistances. see teamwork thread on over-cheap uptake in N
  !  resistors. 
  integer,  private, parameter :: nstp            = 2             ! Number of
  !  calculation part
  integer,  private, parameter :: ncost6          = 6             ! Number of
  !  N transport pathways
  integer,  private, parameter :: pcost3          = 3             ! Number of
  !  P transport pathways

  character(len=*), parameter, private :: sourcefile = &
       __FILE__

!
!--------------------------------------------------------------------
  !---
 contains
!--------------------------------------------------------------------
   !---
 subroutine readParams ( ncid )
  !
  ! !USES:
  use ncdio_pio , only : file_desc_t,ncd_io

  ! !ARGUMENTS:
  implicit none
  type(file_desc_t),intent(inout) :: ncid   ! pio netCDF file id
  !
  ! !LOCAL VARIABLES:
  character(len=32)  :: subname = 'CNFUNParamsType'
  character(len=100) :: errCode = '-Error reading in parameters file:'
  logical            :: readv ! has variable been read in or not
  real(r8)           :: tempr ! temporary to read in parameter
  character(len=100) :: tString ! temp. var for reading
!--------------------------------------------------------------------
  !---

  ! read in parameters

    tString='ndays_on'
    call ncd_io(varname=trim(tString),data=tempr, flag='read', ncid=ncid, readvar=readv)
    if ( .not. readv ) call endrun( msg=trim(errCode)//trim(tString)//errMsg(__FILE__, __LINE__))
    params_inst%ndays_on=tempr

    tString='ndays_off'
    call ncd_io(varname=trim(tString),data=tempr, flag='read', ncid=ncid, readvar=readv)
    if ( .not. readv ) call endrun( msg=trim(errCode)//trim(tString)//errMsg(__FILE__, __LINE__))
    params_inst%ndays_off=tempr


 end subroutine readParams

!--------------------------------------------------------------------
 !---

subroutine CNFUNInit (bounds,cnstate_vars,carbonstate_vars, &
                      nitrogenstate_vars,phosphorusstate_vars)
  !
  ! !DESCRIPTION:
  !
  ! !USES:
  use clm_varcon      , only: secspday, fun_period
  use clm_time_manager, only: get_step_size, get_nstep
  use clm_time_manager, only: get_curr_date, get_days_per_year
  use clm_varctl      , only: iulog, use_funp
  use VegetationDataType  , only : veg_cs, veg_ns, veg_ps
  !
  ! !ARGUMENTS:
  type(bounds_type)           , intent(in)    :: bounds
  type(cnstate_type)          , intent(inout) :: cnstate_vars
  type(carbonstate_type)      , intent(inout) :: carbonstate_vars
  type(nitrogenstate_type)    , intent(inout) :: nitrogenstate_vars
  type(phosphorusstate_type)  , intent(inout) :: phosphorusstate_vars

  !
  ! !LOCAL VARIABLES:
  real(r8)          :: dayspyr                  ! days per year (days)
  real(r8)          :: timestep_fun             ! Timestep length for
  !  FUN (s)
  real(r8)          :: numofyear                ! number of days per
  !  year
  integer           :: nstep                    ! time step number
  integer           :: nstep_fun                ! Number of
  !  atmospheric timesteps between calls to FUN
  character(len=32) :: subname = 'CNFUNInit'
!--------------------------------------------------------------------
  !---

! Set local pointers
  associate(ivt                 => veg_pp%itype                                    , & ! Input:  [integer  (:) ]  pft vegetation type
!
         leafcn                 => veg_vp%leafcn                                   , & ! Input:  [real(r8) (:)   ]  leaf C:N (gC/gN)
!
         leafcp                 => veg_vp%leafcp                                   , & ! Input:  [real(r8) (:)   ]  leaf C:P (gC/gP)
!
         leafcn_offset          => cnstate_vars%leafcn_offset_patch                 , & ! Output:
         !  [real(r8) (:)   ]  Leaf C:N used by FUN 
!
         leafcp_offset          => cnstate_vars%leafcp_offset_patch                 , & ! Output:
         !  [real(r8) (:)   ]  Leaf C:P used by FUN 
!
         leafc_storage_xfer_acc =>          veg_cs%leafc_storage_xfer_acc                    , & ! Output: [real(r8) (:)
         !   ]  Accmulated leaf C transfer (gC/m2) 
!
         storage_cdemand =>  veg_cs%storage_cdemand    , & ! Output: [real(r8) (:)
!
         !   ]  C use from the C storage pool
         leafn_storage_xfer_acc =>  veg_ns%leafn_storage_xfer_acc   , & ! Output: [real(r8) (:)
!
         !  ]  Accmulated leaf N transfer (gC/m2)                 
         storage_ndemand  => veg_ns%storage_ndemand  , & ! Output: [real(r8) (:)
!
         !  ]  N demand during the offset period 
         leafp_storage_xfer_acc => veg_ps%leafp_storage_xfer_acc , & ! Output: [real(r8) (:)
!
         !  ]  Accmulated leaf P transfer (gC/m2)                 
         storage_pdemand =>  veg_ps%storage_pdemand     & ! Output: [real(r8) (:)
         !  ]  P demand during the offset period 
         )
  !--------------------------------------------------------------------
  !---
  ! Calculate some timestep-related values.
  !--------------------------------------------------------------------
  !---

  ! set time steps
  dt           = real(get_step_size(), r8)
  dayspyr      = get_days_per_year()
  nstep        = get_nstep()
  timestep_fun = real(secspday * fun_period)
  nstep_fun    = int(secspday * dayspyr / dt) 

  ndays_on     = params_inst%ndays_on
  ndays_off    = params_inst%ndays_off

  !--------------------------------------------------------------------
  !---
  ! Decide if FUN will be called on this timestep.
  !--------------------------------------------------------------------
  !---
  numofyear = nstep/nstep_fun

  if (mod(nstep,nstep_fun) == 0) then
     leafcn_offset(bounds%begp:bounds%endp)          = leafcn(ivt(bounds%begp:bounds%endp))

     storage_cdemand(bounds%begp:bounds%endp)        = 0._r8
     storage_ndemand(bounds%begp:bounds%endp)        = 0._r8

     leafn_storage_xfer_acc(bounds%begp:bounds%endp) = 0._r8
     leafc_storage_xfer_acc(bounds%begp:bounds%endp) = 0._r8

     if(use_funp)then
     leafcp_offset(bounds%begp:bounds%endp)          = leafcp(ivt(bounds%begp:bounds%endp))
     storage_pdemand(bounds%begp:bounds%endp)        = 0._r8
     leafp_storage_xfer_acc(bounds%begp:bounds%endp) = 0._r8
     end if
  end if  
!--------------------------------------------------------------------
  !---
  end associate
  end subroutine CNFUNInit 
!--------------------------------------------------------------------
  !---

  !--------------------------------------------------------------------
  !---  
  ! Start the CNFUN subroutine
  !--------------------------------------------------------------------
  !---
  subroutine CNFUN(bounds                      , &
                num_soilc, filter_soilc, num_soilp, filter_soilp    , &
                canopystate_vars                                    , &
                cnstate_vars, carbonstate_vars, carbonflux_vars     , &
                c13_carbonflux_vars, c14_carbonflux_vars            , &
                nitrogenstate_vars, nitrogenflux_vars               , &
                phosphorusstate_vars, phosphorusflux_vars, crop_vars, &
                soilhydrology_vars, temperature_vars, waterflux_vars, &
                soilstate_vars)

    ! !USES:
    use shr_sys_mod      , only: shr_sys_flush
    use clm_varctl       , only: iulog,cnallocate_carbon_only,cnallocate_carbonnitrogen_only,&
                                 cnallocate_carbonphosphorus_only
!    use pftvarcon        , only: npcropmin, declfact, bfact, aleaff, arootf, astemf
!    use pftvarcon        , only: arooti, fleafi, allconsl, allconss, grperc, grpnow, nsoybean
    use pftvarcon        , only: noveg
    use pftvarcon        , only: npcropmin, grperc, grpnow
    use clm_varpar       , only: nlevdecomp 
    use clm_varcon       , only: nitrif_n2o_loss_frac, secspday
!    use landunit_varcon  , only: istsoil, istcrop
    use clm_time_manager , only: get_step_size
    !
    ! !ARGUMENTS:
    type(bounds_type)        , intent(in)    :: bounds
    integer                  , intent(in)    :: num_soilc        ! number of soil columns in filter
    integer                  , intent(in)    :: filter_soilc(:)  ! filter for soil columns
    integer                  , intent(in)    :: num_soilp        ! number of soil patches in filter
    integer                  , intent(in)    :: filter_soilp(:)  ! filter for soil patches

    type(canopystate_type)   , intent(in)    :: canopystate_vars
    type(cnstate_type)       , intent(inout) :: cnstate_vars
    type(carbonstate_type)   , intent(in)    :: carbonstate_vars
    type(carbonflux_type)    , intent(inout) :: carbonflux_vars
    type(carbonflux_type)    , intent(inout) :: c13_carbonflux_vars
    type(carbonflux_type)    , intent(inout) :: c14_carbonflux_vars
    type(nitrogenstate_type) , intent(inout) :: nitrogenstate_vars
    type(nitrogenflux_type)  , intent(inout) :: nitrogenflux_vars
!    !!  add phosphorus  -X.YANG
    type(phosphorusstate_type) , intent(inout) :: phosphorusstate_vars
    type(phosphorusflux_type)  , intent(inout) :: phosphorusflux_vars
    type(crop_type)            , intent(inout) :: crop_vars

     !! add varibles needed for FUN
    type(soilhydrology_type)  , intent(in) :: soilhydrology_vars
    type(temperature_type)    , intent(in) :: temperature_vars
    type(waterflux_type)      , intent(in) :: waterflux_vars
    type(soilstate_type)      , intent(in) :: soilstate_vars
    !
  ! !LOCAL VARIABLES:
  ! local pointers to implicit in arrays
  ! 
  !--------------------------------------------------------------------
  ! ------------
  ! Integer parameters
  !--------------------------------------------------------------------
  !-----------
  integer,  parameter :: icostFix        = 1             ! Process
  !  number for fixing.
  integer,  parameter :: icostRetrans    = 2             ! Process
  !  number for retranslocation.
  integer,  parameter :: icostActiveNO3  = 3             ! Process
  !  number for mycorrhizal uptake of NO3.
  integer,  parameter :: icostActiveNH4  = 4             ! Process
  !  number for mycorrhizal uptake of NH4
  integer,  parameter :: icostnonmyc_no3  = 5            ! Process
  !  number for nonmyc uptake of NO3.
  integer,  parameter :: icostnonmyc_nh4  = 6            ! Process
  !  number for nonmyc uptake of NH4.
  integer,  parameter :: icostRetransP   = 1             ! Process
  !  number for retranslocation.
  integer,  parameter :: icostActivePOX  = 2             ! Process
  !  number for mycorrhizal uptake of POX.
  integer,  parameter :: icostnonmyc_pox  = 3            ! Process
  !  number for nonmyc uptake of POX.
  real(r8), parameter :: big_cost        = 1000000000._r8! An arbitrarily large cost

  !  array index when plant is fixing
  integer, parameter :: plants_are_fixing = 1
  integer, parameter :: plants_not_fixing = 2

  !  array index for ECM step versus AM step
  integer, parameter :: ecm_step          = 1
  integer, parameter :: am_step           = 2
  !  arbitrary large cost (gC/gN).
  !--------------------------------------------------------------------
  !-----------------------------------------------
  ! Local Real variables.
  !--------------------------------------------------------------------
  !-----------------------------------------------
  real(r8)  :: excess                                                ! excess N taken up by transpiration    (gN/m2) 
  real(r8)  :: steppday                                              ! model time steps in each day          (-)
  real(r8)  :: rootc_dens_step                                       ! root C for each PFT in each soil layer(gC/m2)
  real(r8)  :: retrans_limit1                                        ! a temporary variable for leafn        (gN/m2)
  real(r8)  :: retrans_limit2                                        ! a temporary variable for leafp        (gP/m2)
  real(r8)  :: qflx_tran_veg_layer                                   ! transpiration in each soil layer      (mm H2O/S)
  real(r8)  :: dn                                                    ! Increment of N                        (gN/m2)  
  real(r8)  :: dn_retrans                                            ! Increment of N                        (gN/m2)
  real(r8)  :: dp                                                    ! Increment of P                        (gP/m2)  
  real(r8)  :: dp_retrans                                            ! Increment of P                        (gP/m2)
  real(r8)  :: dnpp                                                  ! Increment of NPP                      (gC/m2)
  real(r8)  :: dnpp_p                                                  ! Increment of NPP                      (gC/m2)
  real(r8)  :: dnpp_retrans                                          ! Increment of NPP                      (gC/m2)
  real(r8)  :: rootc_dens(bounds%begp:bounds%endp,1:nlevdecomp)      ! the root carbon density               (gC/m2)
  real(r8)  :: rootC(bounds%begp:bounds%endp)                        ! root biomass                          (gC/m2)
  real(r8)  :: permyc(bounds%begp:bounds%endp,1:nstp)                ! the arrary for the ECM and AM ratio   (-) 
  real(r8)  :: kc_active(bounds%begp:bounds%endp,1:nstp)             ! the kc_active parameter               (gC/m2)
  real(r8)  :: kn_active(bounds%begp:bounds%endp,1:nstp)             ! the kn_active parameter               (gC/m2)
  real(r8)  :: kcp_active(bounds%begp:bounds%endp,1:nstp)            ! the kcp_active parameter   
  real(r8)  :: kp_active(bounds%begp:bounds%endp,1:nstp)             ! the kp_active parameter               (gC/m2)
  real(r8)  :: availc_pool(bounds%begp:bounds%endp)                  ! The avaible C pool for allocation     (gC/m2)
  real(r8)  :: plantN(bounds%begp:bounds%endp)                       ! Plant N                               (gN/m2)
 real(r8)  :: availc_pool_p(bounds%begp:bounds%endp)                  ! The avaible C pool for allocation     (gC/m2)
  real(r8)  :: plantP(bounds%begp:bounds%endp)                       ! Plant P                               (gP/m2)
  real(r8)  :: plant_ndemand_pool(bounds%begp:bounds%endp)           ! The N demand pool                     (gN/m2)
  real(r8)  :: plant_pdemand_pool(bounds%begp:bounds%endp)           ! The P demand pool                     (gP/m2)
  real(r8)  :: plant_ndemand_pool_step(bounds%begp:bounds%endp,1:nstp)   ! the N demand pool                     (gN/m2)
  real(r8)  :: plant_pdemand_pool_step(bounds%begp:bounds%endp,1:nstp)   ! the P demand pool                     (gP/m2)
  real(r8)  :: leafn_step(bounds%begp:bounds%endp,1:nstp)            ! N loss based for deciduous trees      (gN/m2)
  real(r8)  :: leafp_step(bounds%begp:bounds%endp,1:nstp)            ! P loss based for deciduous trees      (gP/m2)
  real(r8)  :: leafn_retrans_step(bounds%begp:bounds%endp,1:nstp)    ! N loss based for deciduous trees      (gN/m2) 
  real(r8)  :: leafp_retrans_step(bounds%begp:bounds%endp,1:nstp)    ! P loss based for deciduous trees      (gP/m2) 
  real(r8)  :: litterfall_n(bounds%begp:bounds%endp)                 ! N loss based on the leafc to litter   (gN/m2) 
  real(r8)  :: litterfall_p(bounds%begp:bounds%endp)                 ! P loss based on the leafc to litter   (gP/m2) 
  real(r8)  :: litterfall_n_step(bounds%begp:bounds%endp,1:nstp)       ! N loss based on the leafc to litter   (gN/m2)
  real(r8)  :: litterfall_p_step(bounds%begp:bounds%endp,1:nstp)       ! P loss based on the leafc to litter   (gP/m2)
  real(r8)  :: litterfall_c_step(bounds%begp:bounds%endp,1:nstp)       ! N loss based on the leafc to litter   (gN/m2)
  real(r8)  :: litterfall_c_step_p(bounds%begp:bounds%endp,1:nstp)     ! N loss based on the leafc to litter   (gN/m2)
  real(r8)  :: tc_soisno(bounds%begc:bounds%endc,1:nlevdecomp)       ! Soil temperature            (degrees Celsius)
  real(r8)  :: tc_soila10(bounds%begc:bounds%endc)                   ! 10-day running mean of the 12cm soil layer temp  (degrees Celsius)
  real(r8)  :: npp_remaining(bounds%begp:bounds%endp,1:nstp)         ! A temporary variable for npp_remaining(gC/m2) 
  real(r8)  :: npp_remaining_p(bounds%begp:bounds%endp,1:nstp)       ! A temporary variable for npp_remaining(gC/m2) for P
  real(r8)  :: n_passive_step(bounds%begp:bounds%endp,1:nstp)        ! N taken up by transpiration at substep(gN/m2)
  real(r8)  :: p_passive_step(bounds%begp:bounds%endp,1:nstp)        ! P taken up by transpiration at substep(gP/m2)
  real(r8)  :: n_passive_acc(bounds%begp:bounds%endp)                ! N acquired by passive uptake          (gN/m2)
  real(r8)  :: p_passive_acc(bounds%begp:bounds%endp)                ! P acquired by passive uptake          (gP/m2)
  real(r8)  :: cost_retran(bounds%begp:bounds%endp,1:nlevdecomp)     ! cost of retran                        (gC/gN)
  real(r8)  :: cost_retran_p(bounds%begp:bounds%endp,1:nlevdecomp)     ! cost of retran  P                      (gC/gP)
  real(r8)  :: cost_fix(bounds%begp:bounds%endp,1:nlevdecomp)        ! cost of fixation                      (gC/gN)
  real(r8)  :: cost_resis(bounds%begp:bounds%endp,1:nlevdecomp)      ! cost of resis                         (gC/gN)
  real(r8)  :: cost_resis_p(bounds%begp:bounds%endp,1:nlevdecomp)      ! cost of resis  P                       (gC/gP)
  real(r8)  :: cost_res_resis(bounds%begp:bounds%endp,1:nlevdecomp)  ! The cost of resis                     (gN/gC)
  real(r8)  :: cost_res_resis_p(bounds%begp:bounds%endp,1:nlevdecomp)  ! The cost of resis P                    (gP/gC)
  real(r8)  :: n_fix_acc(bounds%begp:bounds%endp,1:nstp)             ! N acquired by fixation                (gN/m2)
  real(r8)  :: n_fix_acc_total(bounds%begp:bounds%endp)              ! N acquired by fixation                (gN/m2)
  real(r8)  :: npp_fix_acc(bounds%begp:bounds%endp,1:nstp)           ! Amount of NPP used by fixation        (gC/m2)
  real(r8)  :: npp_fix_acc_total(bounds%begp:bounds%endp)            ! Amount of NPP used by fixation        (gC/m2)
  real(r8)  :: n_retrans_acc(bounds%begp:bounds%endp,1:nstp)         ! N acquired by retranslocation         (gN/m2)
  real(r8)  :: p_retrans_acc(bounds%begp:bounds%endp,1:nstp)         ! P acquired by retranslocation         (gP/m2)
  real(r8)  :: n_retrans_acc_total(bounds%begp:bounds%endp)          ! N acquired by retranslocation         (gN/m2)
  real(r8)  :: p_retrans_acc_total(bounds%begp:bounds%endp)          ! P acquired by retranslocation         (gP/m2)
  real(r8)  :: free_nretrans_acc(bounds%begp:bounds%endp,1:nstp)     ! N acquired by retranslocation         (gN/m2)
  real(r8)  :: free_pretrans_acc(bounds%begp:bounds%endp,1:nstp)     ! P acquired by retranslocation         (gP/m2)
  real(r8)  :: npp_retrans_acc(bounds%begp:bounds%endp,1:nstp)       ! NPP used for the extraction           (gC/m2)
  real(r8)  :: npp_retrans_p_acc(bounds%begp:bounds%endp,1:nstp)     ! NPP used for the extraction of P        (gC/m2)
  real(r8)  :: npp_retrans_acc_total(bounds%begp:bounds%endp)        ! NPP used for the extraction           (gC/m2)
  real(r8)  :: npp_retrans_p_acc_total(bounds%begp:bounds%endp)      ! NPP used for the extraction   of P        (gC/m2)
  real(r8)  :: nt_uptake(bounds%begp:bounds%endp,1:nstp)             ! N uptake from retrans, active, and fix(gN/m2)
  real(r8)  :: pt_uptake(bounds%begp:bounds%endp,1:nstp)             ! P uptake from retrans and active (gP/m2)
  real(r8)  :: npp_uptake(bounds%begp:bounds%endp,1:nstp)            ! NPP used by the uptakes               (gC/m2)
  real(r8)  :: npp_uptake_p(bounds%begp:bounds%endp,1:nstp)          ! NPP used by the uptakes of P              (gC/m2)

  !----------NITRIF_DENITRIF-------------!

  real(r8)  :: sminn_no3_diff                                        ! A temporary limit for N uptake                  (gN/m2)
  real(r8)  :: sminn_nh4_diff                                        ! A temporary limit for N uptake                  (gN/m2)
  real(r8)  :: sminp_pox_diff                                        ! A temporary limit for P uptake                  (gP/m2)
  real(r8)  :: active_no3_limit1                                     ! A temporary limit for N uptake                  (gN/m2)
  real(r8)  :: active_nh4_limit1                                     ! A temporary limit for N uptake                  (gN/m2)
  real(r8)  :: active_pox_limit2                                     ! A temporary limit for P uptake                  (gP/m2)
  real(r8)  :: cost_active_no3(bounds%begp:bounds%endp,1:nlevdecomp) ! cost of mycorrhizal                             (gC/gN)
  real(r8)  :: cost_active_nh4(bounds%begp:bounds%endp,1:nlevdecomp) ! cost of mycorrhizal                             (gC/gN)
  real(r8)  :: cost_active_pox(bounds%begp:bounds%endp,1:nlevdecomp) ! cost of mycorrhizal                             (gP/gP)
  real(r8)  :: cost_nonmyc_no3(bounds%begp:bounds%endp,1:nlevdecomp) ! cost of nonmyc                                  (gC/gN)
  real(r8)  :: cost_nonmyc_nh4(bounds%begp:bounds%endp,1:nlevdecomp) ! cost of nonmyc                                  (gC/gN)
  real(r8)  :: cost_nonmyc_pox(bounds%begp:bounds%endp,1:nlevdecomp) ! cost of nonmyc                                  (gC/gP)

  real(r8)  :: sminn_no3_conc(bounds%begc:bounds%endc,1:nlevdecomp)             ! Concentration of no3 in soil water (gN/gH2O)
  real(r8)  :: sminn_no3_conc_step(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp) ! A temporary variable for soil mineral N (gN/gH2O)
  real(r8)  :: sminn_no3_layer(bounds%begc:bounds%endc,1:nlevdecomp)            ! Available no3 in each soil layer (gN/m2)
  real(r8)  :: sminn_no3_layer_step(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp)! A temporary variable for soil no3 (gN/m2) 
  real(r8)  :: sminn_no3_uptake(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp)    ! A temporary variable for soil mineral N (gN/m2/s)
  real(r8)  :: sminn_nh4_conc(bounds%begc:bounds%endc,1:nlevdecomp)             ! Concentration of nh4 in soil water (gN/gH2O)
  real(r8)  :: sminn_nh4_conc_step(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp) ! A temporary variable for soil mineral N (gN/gH2O)
  real(r8)  :: sminn_nh4_layer(bounds%begc:bounds%endc,1:nlevdecomp)            ! Available nh4 in each soil layer (gN/m2)
  real(r8)  :: sminn_nh4_layer_step(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp)! A temporary variable for soil mineral N (gN/m2)
  real(r8)  :: sminn_nh4_uptake(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp)    ! A temporary variable for soil mineral N (gN/m2/s)

  real(r8)  :: sminp_pox_conc(bounds%begc:bounds%endc,1:nlevdecomp)             ! Concentration of pox in soil water (gP/gH2O)
  real(r8)  :: sminp_pox_conc_step(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp) ! A temporary variable for soil mineral P (gP/gH2O)
  real(r8)  :: sminp_pox_layer(bounds%begc:bounds%endc,1:nlevdecomp)            ! Available pox in each soil layer (gP/m2)
  real(r8)  :: sminp_pox_layer_step(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp)! A temporary variable for soil mineral P (gP/m2)
  real(r8)  :: sminp_pox_uptake(bounds%begp:bounds%endp,1:nlevdecomp,1:nstp)    ! A temporary variable for soil mineral P (gP/m2/s)

  real(r8)  :: active_no3_uptake1(bounds%begp:bounds%endp,1:nlevdecomp)         ! no3 mycorrhizal uptake (gN/m2)
  real(r8)  :: active_nh4_uptake1(bounds%begp:bounds%endp,1:nlevdecomp)         ! nh4 mycorrhizal uptake (gN/m2)
  real(r8)  :: active_pox_uptake1(bounds%begp:bounds%endp,1:nlevdecomp)         ! pox mycorrhizal uptake (gP/m2)
  real(r8)  :: nonmyc_no3_uptake1(bounds%begp:bounds%endp,1:nlevdecomp)         ! no3 non-mycorrhizal uptake (gN/m2) 
  real(r8)  :: nonmyc_nh4_uptake1(bounds%begp:bounds%endp,1:nlevdecomp)         ! nh4 non-mycorrhizal uptake (gN/m2) 
  real(r8)  :: nonmyc_pox_uptake1(bounds%begp:bounds%endp,1:nlevdecomp)         ! pox non-mycorrhizal uptake (gP/m2)
  real(r8)  :: active_no3_uptake2(bounds%begp:bounds%endp,1:nlevdecomp)         ! no3 mycorrhizal uptake (gN/m2) 
  real(r8)  :: active_nh4_uptake2(bounds%begp:bounds%endp,1:nlevdecomp)         ! nh4 mycorrhizal uptake (gN/m2) 
  real(r8)  :: active_pox_uptake2(bounds%begp:bounds%endp,1:nlevdecomp)         ! pox mycorrhizal uptake (gP/m2)
  real(r8)  :: nonmyc_no3_uptake2(bounds%begp:bounds%endp,1:nlevdecomp)         ! no3 non-mycorrhizal uptake (gN/m2) 
  real(r8)  :: nonmyc_nh4_uptake2(bounds%begp:bounds%endp,1:nlevdecomp)         ! nh4 non-mycorrhizal uptake (gN/m2) 
  real(r8)  :: nonmyc_pox_uptake2(bounds%begp:bounds%endp,1:nlevdecomp)         ! pox non-mycorrhizal uptake (gP/m2)
  real(r8)  :: n_am_no3_acc(bounds%begp:bounds%endp)                            ! AM no3 uptake (gN/m2)
  real(r8)  :: n_am_nh4_acc(bounds%begp:bounds%endp)                            ! AM nh4 uptake (gN/m2)
  real(r8)  :: p_am_pox_acc(bounds%begp:bounds%endp)                            ! AM pox uptake (gP/m2)
  real(r8)  :: n_ecm_no3_acc(bounds%begp:bounds%endp)                           ! ECM no3 uptake (gN/m2)
  real(r8)  :: n_ecm_nh4_acc(bounds%begp:bounds%endp)                           ! ECM nh4 uptake (gN/m2)
  real(r8)  :: p_ecm_pox_acc(bounds%begp:bounds%endp)                           ! ECM pox uptake (gN/m2)
  real(r8)  :: n_active_no3_acc(bounds%begp:bounds%endp,1:nstp)                 ! Mycorrhizal no3 uptake (gN/m2)
  real(r8)  :: n_active_nh4_acc(bounds%begp:bounds%endp,1:nstp)                 ! Mycorrhizal nh4 uptake (gN/m2)
  real(r8)  :: p_active_pox_acc(bounds%begp:bounds%endp,1:nstp)                 ! Mycorrhizal pox uptake (gP/m2)
  real(r8)  :: n_nonmyc_no3_acc(bounds%begp:bounds%endp,1:nstp)                 ! Non-myc     no3 uptake (gN/m2)
  real(r8)  :: n_nonmyc_nh4_acc(bounds%begp:bounds%endp,1:nstp)                 ! Non-myc     nh4 uptake (gN/m2)
  real(r8)  :: p_nonmyc_pox_acc(bounds%begp:bounds%endp,1:nstp)                 ! Non-myc     pox uptake (gP/m2)
  real(r8)  :: n_active_no3_acc_total(bounds%begp:bounds%endp)                  ! Mycorrhizal no3 uptake (gN/m2)
  real(r8)  :: n_active_nh4_acc_total(bounds%begp:bounds%endp)                  ! Mycorrhizal no3 uptake (gN/m2)
  real(r8)  :: p_active_pox_acc_total(bounds%begp:bounds%endp)                  ! Mycorrhizal pox uptake (gP/m2)
     
  real(r8)  :: n_nonmyc_no3_acc_total(bounds%begp:bounds%endp)                  ! Non-myc     no3 uptake (gN/m2)
  real(r8)  :: n_nonmyc_nh4_acc_total(bounds%begp:bounds%endp)                  ! Non-myc     nh4 uptake (gN/m2)
  real(r8)  :: p_nonmyc_pox_acc_total(bounds%begp:bounds%endp)                  ! Non-myc     pox uptake (gP/m2)
  real(r8)  :: npp_active_no3_acc(bounds%begp:bounds%endp,1:nstp)               ! Mycorrhizal no3 uptake used C (gC/m2)
  real(r8)  :: npp_active_nh4_acc(bounds%begp:bounds%endp,1:nstp)               ! Mycorrhizal nh4 uptake used C (gC/m2)
  real(r8)  :: npp_active_pox_acc(bounds%begp:bounds%endp,1:nstp)               ! Mycorrhizal pox uptake used C (gC/m2)
  real(r8)  :: npp_nonmyc_no3_acc(bounds%begp:bounds%endp,1:nstp)               ! Non-myc     no3 uptake used C (gC/m2)
  real(r8)  :: npp_nonmyc_nh4_acc(bounds%begp:bounds%endp,1:nstp)               ! Non-myc     nh4 uptake used C (gC/m2)
  real(r8)  :: npp_nonmyc_pox_acc(bounds%begp:bounds%endp,1:nstp)               ! Non-myc     pox uptake used C (gC/m2)
  real(r8)  :: npp_active_no3_acc_total(bounds%begp:bounds%endp)                ! Mycorrhizal no3 uptake used C (gC/m2)
  real(r8)  :: npp_active_nh4_acc_total(bounds%begp:bounds%endp)                ! Mycorrhizal nh4 uptake used C (gC/m2)
  real(r8)  :: npp_active_pox_acc_total(bounds%begp:bounds%endp)                ! Mycorrhizal pox uptake used C (gC/m2)
  real(r8)  :: npp_nonmyc_no3_acc_total(bounds%begp:bounds%endp)                ! Non-myc     no3 uptake used C (gC/m2)
  real(r8)  :: npp_nonmyc_nh4_acc_total(bounds%begp:bounds%endp)                ! Non-myc     nh4 uptake used C (gC/m2)
  real(r8)  :: npp_nonmyc_pox_acc_total(bounds%begp:bounds%endp)                ! Non-myc     pox uptake used C (gC/m2)
  real(r8)  :: n_am_no3_retrans(bounds%begp:bounds%endp)                        ! AM no3 uptake for offset (gN/m2)
  real(r8)  :: n_am_nh4_retrans(bounds%begp:bounds%endp)                        ! AM nh4 uptake for offset (gN/m2)
  real(r8)  :: p_am_pox_retrans(bounds%begp:bounds%endp)                        ! AM pox uptake for offset (gP/m2)
  real(r8)  :: n_ecm_no3_retrans(bounds%begp:bounds%endp)                       ! ECM no3 uptake for offset (gN/m2)
  real(r8)  :: n_ecm_nh4_retrans(bounds%begp:bounds%endp)                       ! ECM nh4 uptake for offset (gN/m2)
  real(r8)  :: p_ecm_pox_retrans(bounds%begp:bounds%endp)                       ! ECM pox uptake for offset (gP/m2)
  real(r8)  :: n_active_no3_retrans(bounds%begp:bounds%endp,1:nstp)             ! Mycorrhizal no3 for offset (gN/m2)
  real(r8)  :: n_active_nh4_retrans(bounds%begp:bounds%endp,1:nstp)             ! Mycorrhizal nh4 for offset (gN/m2)
  real(r8)  :: p_active_pox_retrans(bounds%begp:bounds%endp,1:nstp)             ! Mycorrhizal pox for offset (gP/m2)
  real(r8)  :: n_nonmyc_no3_retrans(bounds%begp:bounds%endp,1:nstp)             ! Non-myc     no3 for offset (gN/m2)
  real(r8)  :: n_nonmyc_nh4_retrans(bounds%begp:bounds%endp,1:nstp)             ! Non-myc     nh4 for offset (gN/m2)
  real(r8)  :: p_nonmyc_pox_retrans(bounds%begp:bounds%endp,1:nstp)             ! Non-myc     pox for offset (gP/m2)
  real(r8)  :: n_active_no3_retrans_total(bounds%begp:bounds%endp)              ! Mycorrhizal no3 for offset (gN/m2)
  real(r8)  :: n_active_nh4_retrans_total(bounds%begp:bounds%endp)              ! Mycorrhizal nh4 for offset (gN/m2)
  real(r8)  :: p_active_pox_retrans_total(bounds%begp:bounds%endp)              ! Mycorrhizal pox for offset (gP/m2)
  real(r8)  :: n_nonmyc_no3_retrans_total(bounds%begp:bounds%endp)              ! Non-myc     no3 for offset (gN/m2)
  real(r8)  :: n_nonmyc_nh4_retrans_total(bounds%begp:bounds%endp)              ! Non-myc     nh4 for offset (gN/m2)
  real(r8)  :: p_nonmyc_pox_retrans_total(bounds%begp:bounds%endp)              ! Non-myc     nh4 for offset (gP/m2)
  real(r8)  :: n_passive_no3_vr(bounds%begp:bounds%endp,1:nlevdecomp)           ! Layer passive no3 uptake (gN/m2)
  real(r8)  :: n_passive_nh4_vr(bounds%begp:bounds%endp,1:nlevdecomp)           ! Layer passive nh4 uptake (gN/m2)
  real(r8)  :: p_passive_pox_vr(bounds%begp:bounds%endp,1:nlevdecomp)           ! Layer passive pox uptake (gP/m2)
  real(r8)  :: n_fix_no3_vr(bounds%begp:bounds%endp,1:nlevdecomp)               ! Layer fixation no3 uptake (gN/m2)
  real(r8)  :: n_fix_nh4_vr(bounds%begp:bounds%endp,1:nlevdecomp)               ! Layer fixation nh4 uptake (gN/m2)
  real(r8)  :: n_active_no3_vr(bounds%begp:bounds%endp,1:nlevdecomp)            ! Layer mycorrhizal no3 uptake (gN/m2)
  real(r8)  :: n_nonmyc_no3_vr(bounds%begp:bounds%endp,1:nlevdecomp)            ! Layer non-myc     no3 uptake (gN/m2)
  real(r8)  :: n_active_nh4_vr(bounds%begp:bounds%endp,1:nlevdecomp)            ! Layer mycorrhizal nh4 uptake (gN/m2)
  real(r8)  :: n_nonmyc_nh4_vr(bounds%begp:bounds%endp,1:nlevdecomp)            ! Layer non-myc     nh4 uptake (gN/m2)
  real(r8)  :: p_active_pox_vr(bounds%begp:bounds%endp,1:nlevdecomp)            ! Layer mycorrhizal pox uptake (gP/m2)
  real(r8)  :: p_nonmyc_pox_vr(bounds%begp:bounds%endp,1:nlevdecomp)            ! Layer non-myc     pox uptake (gP/m2)
  real(r8)  :: npp_active_no3_retrans(bounds%begp:bounds%endp,1:nstp)           ! Mycorrhizal no3 uptake used C for offset (gN/m2)
  real(r8)  :: npp_active_nh4_retrans(bounds%begp:bounds%endp,1:nstp)           ! Mycorrhizal nh4 uptake used C for offset (gN/m2)
  real(r8)  :: npp_active_pox_retrans(bounds%begp:bounds%endp,1:nstp)           ! Mycorrhizal pox uptake used C for offset (gP/m2)
  real(r8)  :: npp_nonmyc_no3_retrans(bounds%begp:bounds%endp,1:nstp)           ! Non-myc no3 uptake used C for offset (gN/m2)
  real(r8)  :: npp_nonmyc_nh4_retrans(bounds%begp:bounds%endp,1:nstp)           ! Non-myc nh4 uptake used C for offset (gN/m2)
  real(r8)  :: npp_nonmyc_pox_retrans(bounds%begp:bounds%endp,1:nstp)           ! Non-myc pox uptake used C for offset (gP/m2)
  real(r8)  :: npp_active_no3_retrans_total(bounds%begp:bounds%endp)            ! Mycorrhizal no3 uptake used C for offset (gN/m2)
  real(r8)  :: npp_active_nh4_retrans_total(bounds%begp:bounds%endp)            ! Mycorrhizal nh4 uptake used C for offset (gN/m2)
  real(r8)  :: npp_active_pox_retrans_total(bounds%begp:bounds%endp)            ! Mycorrhizal pox uptake used C for offset (gP/m2)
  real(r8)  :: npp_nonmyc_no3_retrans_total(bounds%begp:bounds%endp)             ! Non-myc no3 uptake used C for offset (gN/m2)
  real(r8)  :: npp_nonmyc_nh4_retrans_total(bounds%begp:bounds%endp)            ! Non-myc nh4 uptake used C for offset (gN/m2)
  real(r8)  :: npp_nonmyc_pox_retrans_total(bounds%begp:bounds%endp)            ! Non-myc pox uptake used C for offset (gP/m2)
  

  real(r8)  :: costNit(1:nlevdecomp,ncost6)                          ! Cost of N via each process                      (gC/gN)
  real(r8)  :: costPho(1:nlevdecomp,pcost3)                          ! Cost of P via each process                      (gC/gP)


  ! Uptake fluxes for COST_METHOD=2
  ! actual npp to each layer for each N uptake process
  real(r8)  ::                   npp_to_fixation(1:nlevdecomp) 
  real(r8)  ::                   npp_to_retrans(1:nlevdecomp)
  real(r8)  ::                   npp_to_active_nh4(1:nlevdecomp)
  real(r8)  ::                   npp_to_nonmyc_nh4(1:nlevdecomp)
  real(r8)  ::                   npp_to_active_no3(1:nlevdecomp)
  real(r8)  ::                   npp_to_nonmyc_no3 (1:nlevdecomp)

  ! actual npp to each layer for each P uptake process
  real(r8)  ::                   npp_to_retrans_p(1:nlevdecomp)
  real(r8)  ::                   npp_to_active_pox(1:nlevdecomp)
  real(r8)  ::                   npp_to_nonmyc_pox(1:nlevdecomp)
  

  ! fraction of carbon to each N uptake process 
  real(r8)  ::                   npp_frac_to_fixation(1:nlevdecomp) 
  real(r8)  ::                   npp_frac_to_retrans(1:nlevdecomp)
  real(r8)  ::                   npp_frac_to_active_nh4(1:nlevdecomp)
  real(r8)  ::                   npp_frac_to_nonmyc_nh4(1:nlevdecomp)
  real(r8)  ::                   npp_frac_to_active_no3(1:nlevdecomp)
  real(r8)  ::                   npp_frac_to_nonmyc_no3 (1:nlevdecomp)  

  ! fraction of carbon to each P uptake process 
  real(r8)  ::                   npp_frac_to_retrans_p(1:nlevdecomp)
  real(r8)  ::                   npp_frac_to_active_pox(1:nlevdecomp)
  real(r8)  ::                   npp_frac_to_nonmyc_pox(1:nlevdecomp)
   
  ! hypothetical fluxes on N in each layer 
  real(r8)  ::                  n_exch_fixation(1:nlevdecomp)        ! N aquired from one unit of C for fixation (unitless)
  real(r8)  ::                  n_exch_retrans(1:nlevdecomp)         ! N aquired from one unit of C for retrans (unitless)
  real(r8)  ::                  n_exch_active_nh4(1:nlevdecomp)      ! N aquired from one unit of C for act nh4(unitless)
  real(r8)  ::                  n_exch_nonmyc_nh4(1:nlevdecomp)      ! N aquired from one unit of C for nonmy nh4 (unitless) 
  real(r8)  ::                  n_exch_active_no3(1:nlevdecomp)      ! N aquired from one unit of C for act no3 (unitless)
  real(r8)  ::                  n_exch_nonmyc_no3(1:nlevdecomp)      ! N aquired from one unit of C for nonmyc no3 (unitless) 

  ! hypothetical fluxes on P in each layer 
  real(r8)  ::                  p_exch_retrans(1:nlevdecomp)         ! P aquired from one unit of C for retrans (unitless)
  real(r8)  ::                  p_exch_active_pox(1:nlevdecomp)      ! P aquired from one unit of C for act pox(unitless)
  real(r8)  ::                  p_exch_nonmyc_pox(1:nlevdecomp)      ! P aquired from one unit of C for nonmy pox (unitless) 
  
   !actual fluxes of N in each layer
  real(r8)  ::                  n_from_fixation(1:nlevdecomp)        ! N aquired in each layer for fixation       (gN m-2 s-1)
  real(r8)  ::                  n_from_retrans(1:nlevdecomp)         ! N aquired in each layer of C for retrans (gN m-2 s-1)
  real(r8)  ::                  n_from_active_nh4(1:nlevdecomp)      ! N aquired in each layer of C for act nh4 (gN m-2 s-1)
  real(r8)  ::                  n_from_nonmyc_nh4(1:nlevdecomp)      ! N aquired in each layer of C for nonmy nh4 (gN m-2 s-1)
  real(r8)  ::                  n_from_active_no3(1:nlevdecomp)      ! N aquired in each layer of C for act no3 (gN m-2 s-1)
  real(r8)  ::                  n_from_nonmyc_no3(1:nlevdecomp)      ! N aquired in each layer of C for nonmyc no3 (gN m-2 s-1) 

   !actual fluxes of P in each layer
  real(r8)  ::                  p_from_retrans(1:nlevdecomp)         ! P aquired in each layer of C for retrans (gP m-2 s-1)
  real(r8)  ::                  p_from_active_pox(1:nlevdecomp)      ! P aquired in each layer of C for act pox (gP m-2 s-1)
  real(r8)  ::                  p_from_nonmyc_pox(1:nlevdecomp)      ! P aquired in each layer of C for nonmy pox (gP m-2 s-1)
 

  real(r8)  :: free_Nretrans(bounds%begp:bounds%endp)                     ! the total amount of NO3 and NH4                 (gN/m3/s)
  real(r8)  :: free_Pretrans(bounds%begp:bounds%endp)                     ! the total amount of POX                         (gP/m3/s)


  ! Uptake fluxes for COST_METHOD=2
  !actual fluxes of N in each layer
  real(r8)  ::                  frac_ideal_C_use                     ! How much less C do we use for 'buying' N than that
  !  needed to get to the ideal ratio?  fraction. 

  real(r8)  ::                  N_acquired
  real(r8)  ::                  P_acquired
  real(r8)  ::                  C_spent
  real(r8)  ::                  C_spentP
  real(r8)  ::                  leaf_narea ! leaf n per unit leaf
  !  area in gN/m2 (averaged across canopy, which is OK for the cost
  !   calculation)
  real(r8)  ::                  leaf_parea ! leaf p per unit leaf
  !  area in gP/m2 (averaged across canopy, which is OK for the cost
  !   calculation)

                       
  real(r8)  ::                  sum_n_acquired                          ! Sum N aquired from one unit of C (unitless)  
  real(r8)  ::                  sum_p_acquired                          ! Sum P aquired from one unit of C (unitless) 
  real(r8)  ::                  burned_off_carbon                       ! carbon wasted by poor allocation algorithm. If
  !  this is too big, we need a better iteration. 
  real(r8)  ::                  burned_off_carbon_p                     ! carbon wasted by poor allocation algorithm. If
  !  this is too big, we need a better iteration. 
  real(r8)   ::                 temp_n_flux  
  real(r8)   ::                 temp_p_flux  
  real(r8)  ::                  delta_cn                                ! difference between 'ideal' leaf CN ratio and
  !  actual leaf C:N ratio. C/N
  real(r8)  ::                  delta_cp                                ! difference between 'ideal' leaf CP ratio and
  !  actual leaf C:P ratio. C/P
  real(r8) :: excess_carbon        ! how much carbon goes into the leaf C
  !  pool on account of the flexibleCN modifications.   
  real(r8) :: excess_carbon_p      ! how much carbon goes into the leaf C
  !  pool on account of the flexibleCP modifications.
  real(r8) :: excess_carbon_acc    ! excess accumulated over layers.
  !  WITHOUT GROWTH RESP
  real(r8) :: excess_carbon_acc_p    ! excess accumulated over layers.
  !  WITHOUT GROWTH RESP
  real(r8) :: fixerfrac            ! what fraction of plants can fix?
  real(r8) :: fixerfrac_p          ! what fraction of plants can fix Phosphorus? 0%! But this is just a test variable!
  real(r8) :: npp_to_spend         ! how much carbon do we need to get
  !  rid of? 
  real(r8) :: npp_to_spend_p       ! how much carbon do we need to get
  !  rid of?
  real(r8) :: npp_to_spend_supplementary ! leftover P-budget C redirected to N uptake
  real(r8) :: soil_n_extraction    ! calculates total N pullled from
  !  soil
  real(r8) :: soil_p_extraction    ! calculates total N pullled from
  !  soil
  real(r8) :: total_N_conductance  !inverse of C to of N for whole soil
  ! -leaf pathway
  real(r8) :: total_P_conductance  !inverse of C to of P for whole soil
  ! -leaf pathway
  real(r8) :: total_N_resistance   ! C to of N for whole soil -leaf
  !  pathway
  real(r8) :: total_P_resistance   ! C to of P for whole soil -leaf
  !  pathway
  real(r8) :: free_RT_frac=0.0_r8  !fraction of N retranslocation which is automatic/free.
  real(r8) :: free_RTP_frac=0.0_r8 !fraction of P retranslocation which is automatic/free.
  !  SHould be made into a PFT parameter. 

  real(r8) :: paid_for_n_retrans
  real(r8) :: free_n_retrans
  real(r8) :: paid_for_p_retrans
  real(r8) :: free_p_retrans
  real(r8) :: total_c_spent_retrans
  real(r8) :: total_c_accounted_retrans
  real(r8) :: total_c_spent_retrans_p
  real(r8) :: total_c_accounted_retrans_p

  real(r8) :: diff_free_paid

  real(r8) :: grperc_n(bounds%begp:bounds%endp)
  real(r8) :: grperc_p(bounds%begp:bounds%endp)

  !Value to scale the phosphorus K parameters 
  real(r8) :: scalex = 100._r8
   
  !Value to scale up the availc C for phosphorus 
  real(r8) :: scale_availc = 1.0_r8

  ! Nfix parameters from Bytnerowicz et al. (2022), 
  ! TODO, put on parameter files
  ! Temperate (and boreal)
  real(r8) :: Tmin_fix = -2.04_r8
  real(r8) :: Topt_fix = 32.10_r8
  real(r8) :: Tmax_fix = 43.98_r8
  ! Tropical parameters
  !real(r8) :: Tmin_fix = 7.04_r8    ! Minimum temperature for tropical Nfix
  !real(r8) :: Topt_fix = 33.22_r8   ! Optimum temperature for tropical Nfix
  !real(r8) :: Tmax_fix = 45.35_r8   ! Max temperature for tropical N fix

  !Local FUN-P variables

  !real(r8), dimension(25) :: perecm
  !real(r8), dimension(25) :: FUN_fracfixers
  !real(r8), dimension(25) :: akc_active
  !real(r8), dimension(25) :: akn_active
  !real(r8), dimension(25) :: ekc_active
  !real(r8), dimension(25) :: ekn_active
  !real(r8), dimension(25) :: kc_nonmyc
  !real(r8), dimension(25) :: kn_nonmyc
  !real(r8), dimension(25) :: kcp_nonmyc
  !real(r8), dimension(25) :: kp_nonmyc


  
  !------end of not_use_nitrif_denitrif------!
  !--------------------------------------------------------------------
  !------------
  ! Local Integer variables
  !--------------------------------------------------------------------
  !------------
  integer   :: fn                                ! number of values
  !  in pft filter
  integer   :: fp                                ! lake filter pft
  !  index
  integer   :: fc                                ! lake filter column
  !  index
  integer   :: p, c                              ! pft index
  integer   :: g, l                              ! indices
  integer   :: j, i, k                           ! soil/snow level
  !  index
  integer   :: istp                              ! Loop counters/work
  integer   :: icost                             ! a local index
  integer   :: fixer                             ! 0 = non-fixer, 1
  ! =fixer 
  logical   :: unmetDemand                       ! True while there
  !  is still demand for N
  logical   :: unmetDemandP                      ! True while there
  !  is still demand for P
  logical   :: local_use_flexibleCN              ! local version of use_flexCN
  integer   :: FIX                               ! for loop. 1 for
  !  fixers, 2 for non fixers. This will become redundant with the
  !   'fixer' parameter if it works. 
  
  !--------------------------------------------------------------------
  !---------------------------------
        
associate(                                                                                 &
         ivt                          => veg_pp%itype                                           , & ! Input:  [integer  (:) ]  pft vegetation type
!
         leafcn                       => veg_vp%leafcn                                  ,  & ! Input:  [real(r8) (:)   ]  leaf C:N (gC/gN)
         leafcp                 => veg_vp%leafcp                                   , & ! Input:  [real(r8) (:)   ]  leaf C:P (gC/gP)
        lflitcn                      =>  veg_vp%lflitcn                               , & ! Input:  [real(r8) (:)   ]  leaf litter C:N (gC/gN) 
        season_decid                 => veg_vp%season_decid                          ,& ! Input:   binary flag for seasonal 
         ! -deciduous leaf habit (0 or 1)
         stress_decid           => veg_vp%stress_decid                           ,& ! Input:   binary flag for stress
         !ALL COMMENTED VARIABLES NEED TO BE DECLARED
         a_fix                  => veg_vp%a_fix                                         , & ! Input:   A BNF parameter
         b_fix                  => veg_vp%b_fix                                         , & ! Input:   A BNF parameter
         c_fix                  => veg_vp%c_fix                                         , & ! Input:   A BNF parameter
         s_fix                  => veg_vp%s_fix                                         , & ! Input:   A BNF parameter
         akc_active             => veg_vp%akc_active                                    , & ! Input:   A mycorrhizal uptake
         !  parameter
         akn_active             => veg_vp%akn_active                                    , & ! Input:   A mycorrhizal uptake
         !  parameter
         akcp_active             => veg_vp%akcp_active                                   , & ! Input:   A mycorrhizal uptake
         !  parameter
         akp_active             => veg_vp%akp_active                                    , & ! Input:   A mycorrhizal uptake
         !  parameter
         ekc_active             => veg_vp%ekc_active                                    , & ! Input:   A mycorrhizal uptake
         !  parameter
        ekn_active             => veg_vp%ekn_active                                    , & ! Input:   A mycorrhizal upatke
         !  parameter
         ekcp_active             => veg_vp%ekcp_active                                   , & ! Input:   A mycorrhizal uptake
         !  parameter
         ekp_active             => veg_vp%ekp_active                                    , & ! Input:   A mycorrhizal upatke
         !  parameter
         kc_nonmyc              => veg_vp%kc_nonmyc                                     , & ! Input:   A non-mycorrhizal uptake
         !  parameter
         kn_nonmyc              => veg_vp%kn_nonmyc                                     , & ! Input:   A non-mycorrhizal uptake
         !  parameter
         kcp_nonmyc              => veg_vp%kcp_nonmyc                                     , & ! Input:   A non-mycorrhizal uptake
         !  parameter
         kp_nonmyc              => veg_vp%kp_nonmyc                                     , & ! Input:   A non-mycorrhizal uptake
         !  parameter
         perecm                 => veg_vp%perecm                                        , & ! Input:   The fraction of ECM
         ! -associated PFT 
         kr_resorb              => veg_vp%kr_resorb                                     , & ! Input:   Parameter for N retranslocation
         krp_resorb             => veg_vp%krp_resorb                                    , & ! Input:   Parameter for P retranslocation
         ! -associated PFT 
         !grperc                 => veg_vp%grperc (DECLARED AS pftcon variable)                      & ! Input:   growth percentage
         fun_cn_flex_a           => veg_vp%fun_cn_flex_a                                , & ! Parameter a of FUN-flexcn link code (def 5)
         fun_cn_flex_b           => veg_vp%fun_cn_flex_b                                , & ! Parameter b of FUN-flexcn link code (def 200)
         fun_cn_flex_c           => veg_vp%fun_cn_flex_c                                , & ! Parameter b of FUN-flexcn link code (def 80)
         fun_cp_flex_a           => veg_vp%fun_cp_flex_a                                , & ! Parameter a of FUN-flexcp link code (def 5)
         fun_cp_flex_b           => veg_vp%fun_cp_flex_b                                , & ! Parameter b of FUN-flexcp link code (def 200)
         fun_cp_flex_c           => veg_vp%fun_cp_flex_c                                , & ! Parameter b of FUN-flexcp link code (def 80)     
         FUN_fracfixers          => veg_vp%FUN_fracfixers                               , & ! Fraction of C that can be used for fixation. 
         leafcn_offset          => cnstate_vars%leafcn_offset_patch                    , & ! Output:
         !  [real(r8)  (:)]  Leaf C:N used by FUN
         leafcp_offset          => cnstate_vars%leafcp_offset_patch                    , & ! Output:
         !  [real(r8)  (:)]  Leaf C:P used by FUN-P
        plantCN                => cnstate_vars%plantCN_patch                          , & ! Output:  [real(r8)  (:)]  Plant
         !  C:N used by FUN
        plantCP                => cnstate_vars%plantCP_patch                          , & ! Output:  [real(r8)  (:)]  Plant
         !  C:P used by FUN-P
        onset_flag             => cnstate_vars%onset_flag_patch                       , & ! Output:  [real(r8)  (:)]  onset
         !  flag
        offset_flag            => cnstate_vars%offset_flag_patch                      , & ! Output:  [real(r8)  (:)]  offset
         !  flag
        availc                 =>              veg_cf%availc                                       , & ! Input:  [real(r8)  (:)]  C flux
         !  available for allocation (gC/m2/s)
        leafc                  => veg_cs%leafc                                        , & ! Input:  [real(r8) (:)   ]  
        leafc_storage          => veg_cs%leafc_storage                               , & ! Input:   [real(r8)
         !  (:)]  (gC/m2) leaf C storage
        frootc                 => veg_cs%frootc                                      , & ! Input:  [real(r8) (:)   ]      
         !  (:)]  (gC/m2) fine root C
        frootc_storage         => veg_cs%frootc_storage                              , & ! Input:   [real(r8)
         !  (:)]  (gC/m2) fine root C storage
        livestemc              =>          veg_cs%livestemc                                   , & ! Input:   [real(r8)
         !  (:)]  (gC/m2) live stem C
       livecrootc             =>        veg_cs%livecrootc                                  , & ! Input:   [real(r8)
         !  (:)]  (gC/m2) live coarse root C
       leafc_storage_xfer_acc => veg_cs%leafc_storage_xfer_acc      , & ! Output:  [real(r8)
         !  (:)]  Accmulated leaf C transfer (gC/m2)
       storage_cdemand        => veg_cs%storage_cdemand             , & ! Output:  [real(r8)
         !  (:)]  C use f rom the C storage pool
       tlai                   => canopystate_vars%tlai_patch                        , & ! Input:  [real(r8) (:)   ] one
         ! -sided leaf area index
        leafn                        => veg_ns%leafn                                       , & ! Input:   [real(r8)  (:)]
         !   (gN/m2) leaf N
        leafp                        =>     veg_ps%leafp                                       , & ! Input:   [real(r8)  (:)]
         !   (gP/m2) leaf P
        frootn                       =>    veg_ns%frootn                                      , & ! Input:   [real(r8)  (:)]
         !   (gN/m2) fine root N
        frootp                       =>    veg_ps%frootp                                      , & ! Input:   [real(r8)  (:)]
         !   (gP/m2) fine root P
       livestemn                    =>     veg_ns%livestemn                                   , & ! Input:   [real(r8)  (:)]
         !   (gN/m2) live stem N
       livestemp                    =>     veg_ps%livestemp                                   , & ! Input:   [real(r8)  (:)]
         !   (gP/m2) live stem P
       livecrootn                  =>     veg_ns%livecrootn                                  , & ! Input:   [real(r8)  (:)]
         !   (gN/m2) live coarse root N
       livecrootp                  =>     veg_ps%livecrootp                                  , & ! Input:   [real(r8)  (:)]
         !   (gP/m2) live coarse root P
        leafn_storage_xfer_acc => veg_ns%leafn_storage_xfer_acc    , & ! Output:  [real(r8)  (:)]
         !   Accmulated leaf N transfer (gC/m2)
        leafp_storage_xfer_acc => veg_ps%leafp_storage_xfer_acc    , & ! Output:  [real(r8)  (:)]
         !   Accmulated leaf P transfer (gC/m2)
       storage_ndemand        => veg_ns%storage_ndemand           , & ! Output:  [real(r8)  (:)]
         !   N demand during the offset period
       storage_pdemand        => veg_ps%storage_pdemand           , & ! Output:  [real(r8)  (:)]
         !   P demand during the offset period
        leafc_to_litter        =>         veg_cf%leafc_to_litter                             , & ! Output:  [real(r8)
         !  (:) ]  leaf C litterfall (gC/m2/s)
         leafc_to_litter_fun   =>     veg_cf%leafc_to_litter_fun                         , & ! Output:  [real(r8)
         !  (:) ]  leaf C litterfall used by FUN (gC/m2/s)
         leafc_to_litter_funp   =>     veg_cf%leafc_to_litter_funp                         , & ! Output:  [real(r8)
         !  (:) ]  leaf C litterfall used by FUN-P (gC/m2/s)
       prev_leafc_to_litter   =>      veg_cf%prev_leafc_to_litter                          , & ! Output: [real(r8) (:)
         !  ] previous timestep leaf C litterfall flux (gC/m2/s)
        leafc_storage_to_xfer  =>     veg_cf%leafc_storage_to_xfer                         , & ! Output:  [real(r8)
         !  (:) ] leaf C shift storage to transfer
         npp_Nactive            =>     veg_cf%npp_Nactive                                  , & ! Output:  [real(r8)
         !  (:) ]  Mycorrhizal N uptake used C (gC/m2/s)
         npp_Pactive            =>     veg_cf%npp_Pactive                                  , & ! Output:  [real(r8)
         !  (:) ]  Mycorrhizal P uptake used C (gC/m2/s)
         npp_Nnonmyc            =>            veg_cf%npp_Nnonmyc                                 , & ! Output:  [real(r8)
         !  (:) ]  Non-mycorrhizal N uptake use C (gC/m2/s)
         npp_Pnonmyc            =>            veg_cf%npp_Pnonmyc                                 , & ! Output:  [real(r8)
         !  (:) ]  Non-mycorrhizal P uptake use C (gC/m2/s)
         npp_Nam                =>          veg_cf%npp_Nam                                     , & ! Output:  [real(r8)
         !  (:) ]  AM uptake use C (gC/m2/s)
         npp_Pam                =>          veg_cf%npp_Pam                                     , & ! Output:  [real(r8)
         !  (:) ]  AM uptake of P use C (gC/m2/s)
         npp_Necm               => veg_cf%npp_Necm                 , & ! Output:  [real(r8)
         !  (:) ]  ECM uptake use C (gC/m2/s)
         npp_Pecm               => veg_cf%npp_Pecm                 , & ! Output:  [real(r8)
         !  (:) ]  ECM uptake of Puse C (gC/m2/s)
         npp_Nactive_no3        => veg_cf%npp_Nactive_no3          , & ! Output:  [real(r8)
         !  (:) ]  Mycorrhizal N uptake used C (gC/m2/s)
         npp_Nnonmyc_no3        => veg_cf%npp_Nnonmyc_no3          , & ! Output:  [real(r8)
         !  (:) ]  Non-myco uptake use C (gC/m2/s) rrhizal N uptake
         !   (gN/m2/s)
         npp_Nam_no3            => veg_cf%npp_Nam_no3              , & ! Output:  [real(r8)
         !  (:) ]  AM uptake use C (gC/m2/s)
         npp_Necm_no3           => veg_cf%npp_Necm_no3             , & ! Output:  [real(r8)
         !  (:) ]  ECM uptake use C (gC/m2/s)
         npp_Nactive_nh4        => veg_cf%npp_Nactive_nh4          , & ! Output:  [real(r8)
         !  (:) ]  Mycorrhizal N uptake used C (gC/m2/s)
         npp_Nnonmyc_nh4        => veg_cf%npp_Nnonmyc_nh4          , & ! Output:  [real(r8)
         !  (:) ]  Non-mycorrhizal N uptake used C (gC/m2/s)
         npp_Nam_nh4            => veg_cf%npp_Nam_nh4              , & ! Output:  [real(r8)
         !  (:) ]  AM uptake used C(gC/m2/s)
         npp_Necm_nh4           => veg_cf%npp_Necm_nh4             , & ! Output:  [real(r8)
         !  (:) ]  ECM uptake used C (gC/m2/s)
         npp_Nfix               => veg_cf%npp_Nfix                 , & ! Output:  [real(r8)
         !  (:) ]  Symbiotic BNF used C (gC/m2/s)
         npp_Nretrans           => veg_cf%npp_Nretrans             , & ! Output:  [real(r8)
         !  (:) ]  Retranslocation N uptake used C (gC/m2/s)
         npp_Pretrans           => veg_cf%npp_Pretrans             , & ! Output:  [real(r8)
         !  (:) ]  Retranslocation P uptake used C (gC/m2/s)
         npp_Nuptake            => veg_cf%npp_Nuptake              , & ! Output:  [real(r8)
         !  (:) ]  Total N uptake of FUN used C (gC/m2/s)
         npp_Puptake            => veg_cf%npp_Puptake              , & ! Output:  [real(r8)
         !  (:) ]  Total N uptake of FUN used C (gC/m2/s)
         npp_growth             => veg_cf%npp_growth               , & ! Output:  [real(r8)
         !  (:) ]  Total N uptake of FUN used C (gC/m2/s) 
         npp_growth_p           => veg_cf%npp_growth_p               , & ! Output:  [real(r8)
         !  (:) ]  Total P uptake of FUN-P used C (gC/m2/s)
         burnedoff_carbon       => veg_cf%npp_burnedoff            , & ! Output:  [real(r8)
         !  (:) ]  C  that cannot be used for N uptake(gC/m2/s)
         burnedoff_carbon_p     => veg_cf%npp_burnedoff_p          , & ! Output:  [real(r8)
         !  (:) ]  C  that cannot be used for P uptake(gC/m2/s)   
         leafc_change           => veg_cf%leafc_change             , & ! Output:  [real(r8)
         !  (:) ]  Used C from the leaf (gC/m2/s)
         leafn_storage_to_xfer  =>          veg_nf%leafn_storage_to_xfer                        ,  & ! Output:  [real(r8) (:) ]
       !  (:) ] leaf N shift storage to transfer
         leafp_storage_to_xfer  =>          veg_pf%leafp_storage_to_xfer                        ,  & ! Output:  [real(r8) (:) ]
       !  (:) ] leaf P shift storage to transfer
          plant_ndemand          =>         veg_nf%plant_ndemand                       , & ! Intput:  [real(r8) (:)
         !  ]  N flux required to support initial GPP (gN/m2/s)
          plant_pdemand          =>         veg_pf%plant_pdemand                       , & ! Intput:  [real(r8) (:)
         !  ]  P flux required to support initial GPP (gP/m2/s)
         plant_ndemand_retrans  =>       veg_nf%plant_ndemand_retrans              , & ! Output:  [real(r8) (:)
         !  ]  N demand generated for FUN (gN/m2/s)
         plant_pdemand_retrans  =>       veg_pf%plant_pdemand_retrans              , & ! Output:  [real(r8) (:)
         !  ]  P demand generated for FUN-P (gP/m2/s)
         plant_ndemand_season   =>             veg_nf%plant_ndemand_season               , & ! Output:  [real(r8) (:)
         !  ]  N demand for seasonal deciduous forest (gN/m2/s)
         plant_pdemand_season   =>             veg_pf%plant_pdemand_season               , & ! Output:  [real(r8) (:)
         !  ]  P demand for seasonal deciduous forest (gP/m2/s)
         plant_ndemand_stress   =>             veg_nf%plant_ndemand_stress               , & ! Output:  [real(r8) (:)
         !  ]  N demand for stress deciduous forest   (gN/m2/s)
         plant_pdemand_stress   =>             veg_pf%plant_pdemand_stress               , & ! Output:  [real(r8) (:)
         !  ]  P demand for stress deciduous forest   (gP/m2/s)
         Nactive                =>               veg_nf%Nactive                            , & ! Output:  [real(r8) (:)
         !  ]  Mycorrhizal N uptake (gN/m2/s)
         Pactive                =>               veg_pf%Pactive                            , & ! Output:  [real(r8) (:)
         !  ]  Mycorrhizal P uptake (gP/m2/s)
         Nnonmyc                =>             veg_nf%Nnonmyc                           , & ! Output:  [real(r8) (:)
         !  ]  Non-mycorrhizal N uptake (gN/m2/s)
         Pnonmyc                =>             veg_pf%Pnonmyc                           , & ! Output:  [real(r8) (:)
         !  ]  Non-mycorrhizal P uptake (gP/m2/s)
         Nam                    =>             veg_nf%Nam                               , & ! Output:  [real(r8) (:) ]  AM
         !  uptake (gN/m2/s)
         Pam                    =>             veg_pf%Pam                               , & ! Output:  [real(r8) (:) ]  AM
         !  uptake (gP/m2/s)
         Necm                   =>             veg_nf%Necm                              , & ! Output:  [real(r8) (:) ]  ECM
         !  uptake (gN/m2/s)
         Pecm                   =>             veg_pf%Pecm                              , & ! Output:  [real(r8) (:) ]  ECM
         !  uptake (gP/m2/s)
         Nactive_no3            =>             veg_nf%Nactive_no3                       , & ! Output:  [real(r8) (:)
         !  ]  Mycorrhizal N uptake (gN/m2/s)
         Nnonmyc_no3            =>            veg_nf%Nnonmyc_no3                       , & ! Output:  [real(r8) (:)
         !  ]  Non-mycorrhizal N uptake (gN/m2/s)
         Nam_no3                =>                 veg_nf%Nam_no3                           , & ! Output:  [real(r8) (:)
         !  ]  AM uptake (gN/m2/s)
         Necm_no3               =>              veg_nf%Necm_no3                          , & ! Output:  [real(r8) (:)
         !  ]  ECM uptake (gN/m2/s)
         Nactive_nh4            =>              veg_nf%Nactive_nh4                       , & ! Output:  [real(r8) (:)
         !  ]  Mycorrhizal N uptake (gN/m2/s)
         Nnonmyc_nh4            =>              veg_nf%Nnonmyc_nh4                      , & ! Output:  [real(r8) (:)
         !  ]  Non-mycorrhizal N uptake (gN/m2/s)
         Nam_nh4                =>            veg_nf%Nam_nh4                          , & ! Output:  [real(r8) (:)
         !  ]  AM uptake (gN/m2/s)
         Necm_nh4               =>             veg_nf%Necm_nh4                         , & ! Output:  [real(r8) (:)
         !  ]  ECM uptake (gN/m2/s)
         Npassive               =>             veg_nf%Npassive                         , & ! Output:  [real(r8) (:)
         !  ]  Passive N uptake (gN/m2/s)
         Ppassive               =>             veg_pf%Ppassive                         , & ! Output:  [real(r8) (:)
         !  ]  Passive P uptake (gP/m2/s)
         Nfix                   =>             veg_nf%Nfix                             , & ! Output:  [real(r8) (:) ]
         !  Symbiotic BNF (gN/m2/s)
         cost_nfix              =>            veg_nf%cost_Nfix                        , & ! Output:  [real(r8) (:)
         !  ]  Cost of fixation gC:gN
         cost_nactive           =>               veg_nf%cost_Nactive                    , & ! Output:  [real(r8) (:) ]
         !  Cost of active uptake gC:gN 
         cost_pactive           =>               veg_pf%cost_Pactive                    , & ! Output:  [real(r8) (:) ]
         !  Cost of active uptake gC:gP       
         cost_nretrans          =>                veg_nf%cost_Nretrans                   , & ! Output:  [real(r8) (:) ]
         !  Cost of retranslocation gC:gN
         cost_pretrans          =>                veg_pf%cost_Pretrans                   , & ! Output:  [real(r8) (:) ]
         !  Cost of retranslocation gC:gP 
         cost_nnonmyc          =>                veg_nf%cost_Nnonmyc                   , & ! Output:  [real(r8) (:) ]
         !  Cost of nonmyc gC:gN
         cost_pnonmyc          =>                veg_pf%cost_Pnonmyc                   , & ! Output:  [real(r8) (:) ]
         !  Cost of nonmyc gC:gP
         nuptake_npp_fraction_patch =>          veg_nf%nuptake_npp_fraction            , & ! Output:  [real(r8) (:)
         !  ]  frac of NPP in NUPTAKE 
         puptake_npp_fraction_patch =>          veg_pf%puptake_npp_fraction            , & ! Output:  [real(r8) (:)
         !  ]  frac of NPP in PUPTAKE 
        c_allometry            =>   cnstate_vars%c_allometry_patch          , & ! Output: [real(r8) (:)   ]  C
         !  allocation index (DIM)    
        n_allometry            =>    cnstate_vars%n_allometry_patch          , & ! Output: [real(r8) (:)   ]  N
         !  allocation index (DIM)  
        p_allometry            =>    cnstate_vars%p_allometry_patch          , & ! Output: [real(r8) (:)   ]  P
         !  allocation index (DIM) 
         leafn_storage          =>                veg_ns%leafn_storage                  , & ! Input:  [real(r8) (:)
         !  ]  (gN/m2) leaf N store
         leafp_storage          =>                veg_ps%leafp_storage                  , & ! Input:  [real(r8) (:)
         !  ]  (gN/m2) leaf P store
         nfix_to_sminn          =>                 col_nf%nfix_to_sminn                  , & ! Output:  [real(r8) (:)]
         !  symbiotic/asymbiotic N fixation to soil mineral N (gN/m2
         !  /s)
         Nretrans               =>             veg_nf%Nretrans                      , & ! Output:  [real(r8) (:)
         !  ]  Retranslocation N uptake (gN/m2/s)
         Pretrans               =>             veg_pf%Pretrans                      , & ! Output:  [real(r8) (:)
         !  ]  Retranslocation P uptake (gP/m2/s)
         Nretrans_season        =>             veg_nf%Nretrans_season               , & ! Output:  [real(r8) (:)
         !  ]  Retranslocation N uptake (gN/m2/s)
         Pretrans_season        =>             veg_pf%Pretrans_season               , & ! Output:  [real(r8) (:)
         !  ]  Retranslocation P uptake (gP/m2/s)
         Nretrans_stress        =>             veg_nf%Nretrans_stress               , & ! Output:  [real(r8) (:)
         !  ]  Retranslocation N uptake (gN/m2/s)
         pretrans_stress        =>             veg_pf%Pretrans_stress               , & ! Output:  [real(r8) (:)
         !  ]  Retranslocation P uptake (gP/m2/s)

         Nuptake                =>             veg_nf%Nuptake                      , & ! Output:  [real(r8) (:)
         !  ]  Total N uptake of FUN (gN/m2/s)
        Puptake                =>             veg_pf%Puptake                      , & ! Output:  [real(r8) (:)
         !  ]  Total P uptake of FUN-P (gP/m2/s)

       retransn_to_npool      =>        veg_nf%retransn_to_npool             , & ! Output: [real(r8)
         !  (:)   ]  deployment of retranslocated N (gN/m2/s)
       retransp_to_ppool      =>        veg_pf%retransp_to_ppool             , & ! Output: [real(r8)
         !  (:)   ]  deployment of retranslocated P (gP/m2/s)

         free_retransn_to_npool =>     veg_nf%free_retransn_to_npool         , & ! Output: [real(r8)
         ! uptake of free N from leaves (needed to allow RT during the night with no NPP
         free_retransp_to_ppool =>     veg_pf%free_retransp_to_ppool         , & ! Output: [real(r8)
         ! uptake of free P from leaves (needed to allow RT during the night with no NPP
         sminn_to_plant_fun     => veg_nf%sminn_to_plant_fun              , & ! Output:
         !  [real(r8) (:) ]  Total soil N uptake of FUN (gN/m2/s)
         sminp_to_plant_fun     => veg_pf%sminp_to_plant_fun              , & ! Output:
         !  [real(r8) (:) ]  Total soil P uptake of FUN (gP/m2/s)
         sminn_to_plant_fun_vr  => veg_nf%sminn_to_plant_fun_vr           , & ! Output:
         !  [real(r8) (:) ]  Total layer soil N uptake of FUN (gN/m2
         !  /s) 
         sminp_to_plant_fun_vr  => veg_pf%sminp_to_plant_fun_vr           , & ! Output:
         !  [real(r8) (:) ]  Total layer soil P uptake of FUN (gP/m2
         !  /s) 
         sminn_to_plant_fun_no3_vr  => veg_nf%sminn_to_plant_fun_no3_vr   , & ! Output:  [real(r8)
         !  (:) ]  Total layer no3 uptake of FUN (gN/m2/s)
         sminn_to_plant_fun_nh4_vr  => veg_nf%sminn_to_plant_fun_nh4_vr   , & ! Output:  [real(r8)
         !  (:) ]  Total layer nh4 uptake of FUN (gN/m2/s)
        sminn_to_plant_vr      => col_nf%sminn_to_plant_vr      , & ! Output:  [real(r8) (:
         ! ,:) ]
        sminp_to_plant_vr      => col_pf%sminp_to_plant_vr      , & ! Output:  [real(r8) (:
         ! ,:) ]
        smin_no3_to_plant_vr   => col_nf%smin_no3_to_plant_vr     , & ! Output:  [real(r8) (:
         ! ,:) ]
       smin_nh4_to_plant_vr   => col_nf%smin_nh4_to_plant_vr     , & ! Output:  [real(r8) (:
         ! ,:) ]
       smin_vr_nh4                  => col_ns%smin_nh4_vr             , & ! Input:  [real(r8) (:,:) ]  (gN/m3) soil mineral
         !  NH4              
       smin_vr_no3                  => col_ns%smin_no3_vr             , & ! Input:  [real(r8) (:,:) ]  (gN/m3) soil mineral (?) OR smin_vr_no3                  => clm_bgc_data%smin_no3_vr_col             , & ! Input:  [real(r8) (:,:) ]  (gN/m3) soil mineral (?)
         !  NO3  
        smin_vr_pox                 => col_ps%sminp_vr             , & ! Input:  [real(r8) (:,:) ]  (gN/m3) soil mineral (?) OR     
       solutionp_vr                 =>                     col_ps%solutionp_vr                   , & ! Input:  [real(r8) (:,:) ]  (gN/m3) soil soluble mineral P ready for plant uptake     
         soilc_change           => veg_cf%soilc_change               , & ! Output:  [real(r8)
         !  (:) ]  Used C from the soil (gC/m2/s)
         soilc_change_p         => veg_cf%soilc_change_p               , & ! Output:  [real(r8)
         !  (:) ]  Used C from the soil for P(gC/m2/s)
       h2osoi_liq             => col_ws%h2osoi_liq                                , & ! Input:   [real(r8) (:,:)]
         !   liquid water (kg/m2) (new) (-nlevsno+1:nlevgrnd) (?)
       qflx_tran_veg          => veg_wf%qflx_tran_veg                        , & ! Input:   [real(r8) (:)  ]
         !   vegetation transpiration (mm H2O/s) (+ = to atm) 
         t_soisno              =>    col_es%t_soisno                         , & ! Input:  [real(r8)  (:,:) ]  soil temperature (Kelvin)  (-nlevsno+1:nlevgrnd)
         soila10               =>    col_es%soila10                          , & ! Input:  [real(r8)  (:,:) ]  10-day running mean of the 12cm soil layer temp (K) 
         crootfr               =>    soilstate_vars%rootfr_patch                                    & ! Input:   [real(r8) (:,:)]
         !   fraction of roots in each soil layer  (nlevgrnd)
         ! But is it the same as for fraction of roots for carbon 
         !in each soil layer?
       
         )



        !perecm = (/1.00_r8, 1.00_r8, 1.00_r8, 1.00_r8, 0.0_r8, &
        !           0.0_r8, 0.0_r8, 0.5_r8, 1.00_r8, 1.00_r8, &
        !           1.00_r8, 1.00_r8, 1.00_r8, 0.0_r8, 0.0_r8, &
        !           0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8, &
        !           0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8/)

        !perecm = (/0.99_r8, 0.99_r8, 0.99_r8, 0.01_r8, &
        !           0.01_r8, 0.01_r8, 0.50_r8, 0.99_r8, 0.99_r8, &
        !           0.99_r8, 0.99_r8, 0.99_r8, 0.01_r8, 0.01_r8, &
        !           0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, &
        !           0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, 0.99_r8/)

        !write(iulog,*) 'perecm=', perecm 

        !akc_active = (/0.0_r8, 0.06_r8, 0.06_r8, 0.06_r8, 0.06_r8, &
        !               0.06_r8, 0.006_r8, 0.06_r8, 0.06_r8, 0.06_r8, &
        !               0.06_r8, 0.06_r8, 0.06_r8, 0.06_r8, 0.6_r8, &
        !               0.06_r8, 0.06_r8, 0.6_r8, 0.6_r8, 0.06_r8, &
        !               0.06_r8, 0.06_r8, 0.06_r8, 0.06_r8, 0.06_r8/)

        !akn_active = (/0.0_r8, 0.12_r8, 0.12_r8, 0.12_r8, 0.12_r8, &
        !               0.12_r8, 0.012_r8, 0.12_r8, 0.12_r8, 0.12_r8, &
        !               0.12_r8, 0.12_r8, 0.12_r8, 0.12_r8, 1.2_r8, &
        !               0.12_r8, 0.12_r8, 1.2_r8, 1.2_r8, 0.12_r8, &
        !               0.12_r8, 0.12_r8, 0.12_r8, 0.12_r8, 0.12_r8/)

        !ekc_active = (/0.0_r8, 0.36_r8, 0.36_r8, 0.036_r8, 0.36_r8, &
        !               0.36_r8, 0.036_r8, 0.36_r8, 0.36_r8, 0.36_r8, & 
        !               0.36_r8, 0.36_r8, 0.36_r8, 0.36_r8, 3.6_r8, &
        !               0.36_r8, 0.36_r8, 3.6_r8, 3.6_r8, 0.36_r8, &
        !               0.36_r8, 0.36_r8, 0.36_r8, 0.36_r8, 0.36_r8/)

        !ekn_active = (/0.0_r8, 0.06_r8, 0.06_r8, 0.006_r8, 0.06_r8, &
        !               0.06_r8, 0.006_r8, 0.06_r8, 0.06_r8, 0.06_r8, &
        !               0.06_r8, 0.06_r8, 0.06_r8, 0.06_r8, 0.6_r8, &
        !               0.06_r8, 0.06_r8, 0.6_r8, 0.6_r8, 0.06_r8, &
        !               0.06_r8, 0.06_r8, 0.06_r8, 0.06_r8, 0.06_r8/) 

       !Following Kara Allen's FUN3 values

       !ekc_active = (/0.0_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, &
       !                0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, & 
       !                0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, &
       !                0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, &
       !                0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8/)

        !ekn_active = (/0.0_r8, 0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, &
        !               0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, &
        !               0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, &
        !               0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, &
        !               0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8, 0.1_r8/) 

        !kc_nonmyc = (/0.0_r8, 0.72_r8, 0.72_r8, 0.72_r8, 0.72_r8, &
        !              0.72_r8, 0.072_r8, 0.72_r8, 0.72_r8, 0.72_r8, &
        !              0.72_r8, 0.72_r8, 0.72_r8, 0.72_r8, 7.2_r8, &
        !              0.72_r8, 0.72_r8, 7.2_r8, 7.2_r8, 0.72_r8, &
        !              0.72_r8, 0.72_r8, 0.72_r8,  0.72_r8, 0.72_r8/)

        !kn_nonmyc = (/0.0_r8, 0.012_r8, 0.012_r8, 0.0012_r8, 0.012_r8, &
        !              0.012_r8, 0.0012_r8, 0.012_r8, 0.012_r8, 0.012_r8, &
        !              0.012_r8, 0.012_r8, 0.012_r8, 0.012_r8, 0.12_r8, &
        !              0.012_r8, 0.012_r8, 0.12_r8, 0.12_r8, 0.012_r8, & 
        !              0.012_r8, 0.012_r8, 0.012_r8, 0.012_r8, 0.012_r8/)

        !FUN_fracfixers = (/0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, &
        !                   0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, & 
        !                   0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, &
        !                   0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8, &
        !                   0.0_r8, 0.0_r8, 0.0_r8, 1.0_r8, 1.0_r8, 1.0_r8/)

 !akcp_active = 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 
 !   0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 ;

 !akp_active = 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 
 !   0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1 ;

 !ekcp_active = 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 
 !   5, 5, 5, 5 ;

 !ekp_active = 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 
 !   0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 
 !   0.07, 0.07, 0.07 ;

         !kcp_nonmyc = (/0.0_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, &
         !               0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, & 
         !               0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, &
         !               0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, &
         !               0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8, 0.3_r8/)

         !kp_nonmyc = (/0.0_r8, 0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, &
         !               0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, & 
         !               0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, &
         !               0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, &
         !               0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8, 0.8_r8/)

   

            !FUN 
               !CHECKING THAT VARIABLES NEEDED FOR FUN ARE CORRECT
           ! do fp=1,num_soilp
           !    p = filter_soilp(fp)
           !    c = veg_pp%column(p)

               !write(iulog,*) 'Fixer fraction', FUN_fracfixers(ivt(p)), &
               !               'perecm', perecm(ivt(p)), &
           !                   'Soil N', smin_vr_no3(c,:)+smin_vr_nh4(c,:), &
           !                   'Soil P', solutionp_vr(c,:), &
           !                   'Fine Root Biomass', frootc(p), &
           !                   'Frac Root nlevgrd', crootfr(p,:), &      
           !                   'leaf N', leafn(p), &
           !                   'leaf P', leafp(p), &
           !                   'NPP0', availc(p), & !(?) 
           !                   'plantcn', leafcn(ivt(p)), &
           !                   'plantcp', leafcp(ivt(p)), &
           !                   'plantnp', leafcp(ivt(p))/leafcn(ivt(p)), &
           !                   'Soil water depth', h2osoi_liq(c,1), & 
           !                   'Soil T', t_soisno(c,1), & 
           !                   'ET', qflx_tran_veg(p), & !NaN
                              !'c3psn', veg_vp%c3psn, &
                  !            'ivt(p)', ivt(p)
           !                  'perECM', perecm
                              !'veg_vp%perECM',  &                             
                              !'perECM', veg_vp%perecm, &
                              !'akc_active',akc_active, &
                              !'fun_cn_flex_a', fun_cn_flex_a
              !1) Which available carbon?
              !2) Physical variables before/after nutrients?
              !3) Fixers and NonFixer as in CLM5.0.
             !end do

 
          

  !--------------------------------------------------------------------
  !-----------
  ! Initialize output fluxes, which were also initialized in CNFUNMod.
  !--------------------------------------------------------------------
  !-----------

  !No flexibleCN
  !local_use_flexibleCN            = use_flexibleCN
  !steppday                        = 48._r8
  steppday                        = 24._r8
  qflx_tran_veg_layer             = 0._r8
  rootc_dens_step                 = 0._r8
  plant_ndemand_pool              = 0._r8

  if(use_funp)then
     plant_pdemand_pool           = 0._r8
  end if

  call t_startf('CNFUNzeroarrays')
  do fp = 1,num_soilp        ! PFT Starts
     p = filter_soilp(fp)
     availc_pool(p)                  = 0._r8
     rootC(p)                        = 0._r8
     litterfall_n(p)                 = 0._r8
     burnedoff_carbon(p)             = 0._r8

     if(use_funp)then
        availc_pool_p(p)             = 0._r8
        litterfall_p(p)              = 0._r8
        burnedoff_carbon_p(p)        = 0._r8
     end if

  end do


  do j = 1, nlevdecomp
     do fp = 1,num_soilp        ! PFT Starts
        p = filter_soilp(fp)
        c = veg_pp%column(p)
        rootc_dens(p,j)                 = 0._r8 
        cost_retran(p,j)                = 0._r8
        cost_fix(p,j)                   = 0._r8
        cost_resis(p,j)                 = 0._r8
        cost_res_resis(p,j)             = 0._r8
        cost_active_no3(p,j)            = 0._r8
        cost_active_nh4(p,j)            = 0._r8
        cost_nonmyc_no3(p,j)            = 0._r8
        cost_nonmyc_nh4(p,j)            = 0._r8
   
        sminn_no3_conc(c,j)             = 0._r8
        sminn_no3_layer(c,j)            = 0._r8
        sminn_nh4_conc(c,j)             = 0._r8
        sminn_nh4_layer(c,j)            = 0._r8

        if(use_funp)then 
           cost_retran_p(p,j)           = 0._r8
           cost_resis_p(p,j)            = 0._r8
           cost_res_resis_p(p,j)        = 0._r8
           cost_active_pox(p,j)         = 0._r8
           cost_nonmyc_pox(p,j)         = 0._r8
   
           sminp_pox_conc(c,j)          = 0._r8
           sminp_pox_layer(c,j)         = 0._r8
        end if

     end do
  end do

  do istp = 1, nstp
     do fp = 1,num_soilp        ! PFT Starts
        p = filter_soilp(fp)
        npp_remaining(p,istp)           = 0._r8
        permyc(p,istp)                  = 0._r8
        plant_ndemand_pool_step(p,istp) = 0._r8
        nt_uptake(p,istp)               = 0._r8
        npp_uptake(p,istp)              = 0._r8
        leafn_step(p,istp)              = 0._r8
        leafn_retrans_step(p,istp)      = 0._r8
        litterfall_n_step(p,istp)       = 0._r8
        litterfall_c_step(p,istp)       = 0._r8

        if(use_funp)then
           npp_remaining_p(p,istp)         = 0._r8
           plant_pdemand_pool_step(p,istp) = 0._r8
           pt_uptake(p,istp)               = 0._r8
           npp_uptake_p(p,istp)            = 0._r8
           leafp_step(p,istp)              = 0._r8
           leafp_retrans_step(p,istp)      = 0._r8
           litterfall_p_step(p,istp)       = 0._r8
           litterfall_c_step_p(p,istp)     = 0._r8
        end if

     end do
     do j = 1, nlevdecomp
        do fp = 1,num_soilp        ! PFT Starts
           p = filter_soilp(fp)
           sminn_no3_conc_step(p,j,istp)      = 0._r8
           sminn_no3_layer_step(p,j,istp)     = 0._r8
           sminn_no3_uptake(p,j,istp)         = 0._r8
           sminn_nh4_conc_step(p,j,istp)      = 0._r8
           sminn_nh4_layer_step(p,j,istp)     = 0._r8
           sminn_nh4_uptake(p,j,istp)         = 0._r8

           if(use_funp)then 
              sminp_pox_conc_step(p,j,istp)   = 0._r8
              sminp_pox_layer_step(p,j,istp)  = 0._r8
              sminp_pox_uptake(p,j,istp)      = 0._r8
           end if

        end do
     end do
  end do

  do icost = 1, ncost6
     do j = 1, nlevdecomp
        costNit(j,icost)                    = big_cost 
     end do
  end do

  if(use_funp)then
  do icost = 1, pcost3
     do j = 1, nlevdecomp
        costPho(j,icost)                    = big_cost 
     end do
  end do
  end if

  ! Time step of FUN
  dt           =  real(get_step_size(), r8)
  call t_stopf('CNFUNzeroarrays')
  !--------------------------------------------------------------------
  !----------------------------
  ! Calculation starts
  !--------------------------------------------------------------------
  call t_startf('CNFUNcalcs1')
  !----------------------------
  do fp = 1,num_soilp        ! PFT Starts
     p = filter_soilp(fp)

     litterfall_n(p) =  (leafc_to_litter_fun(p) / leafcn_offset(p))  * dt
     rootC(p)        =  frootc(p)

     plantN(p)       =  leafn(p) + frootn(p) + livestemn(p) + livecrootn(p)
     if (n_allometry(p).gt.0._r8) then 
         plantCN(p)  = c_allometry(p)/n_allometry(p) !changed RF.
         ! above code gives CN ratio too low. 
     else
         plantCN(p)  = 0._r8 
     end if

     if(use_funp)then
        litterfall_p(p) =  (leafc_to_litter_funp(p) / leafcp_offset(p))  * dt

        plantP(p)       =  leafp(p) + frootp(p) + livestemp(p) + livecrootp(p)
     if (p_allometry(p).gt.0._r8) then 
         plantCP(p)  = c_allometry(p)/p_allometry(p) 
         ! above code gives CP ratio too low. 
     else
         plantCP(p)  = 0._r8 
     end if
     end if
  end do   ! PFT ends
  do istp = 1, nstp
     do fp = 1,num_soilp        ! PFT Starts
        p = filter_soilp(fp)


        !perecm = (/0.99_r8, 0.99_r8, 0.99_r8, 0.01_r8, &
        !           0.01_r8, 0.01_r8, 0.50_r8, 0.99_r8, 0.99_r8, &
        !           0.99_r8, 0.99_r8, 0.99_r8, 0.01_r8, 0.01_r8, &
        !           0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, &
        !           0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, 0.01_r8, 0.99_r8/)
       if(ivt(p).eq.0)then
         perecm(ivt(p)) = 0.0_r8
       else if(ivt(p).eq.1 .or.ivt(p).eq.2.or.ivt(p).eq.3.or.ivt(p).eq.8 .or.ivt(p).eq.9 .or.ivt(p).eq.10.or.ivt(p).eq.11.or.ivt(p).eq.12)then
         perecm(ivt(p)) = 0.99_r8
       else if(ivt(p).eq.7)then
         perecm(ivt(p)) = 0.50_r8
       else
         perecm(ivt(p)) = 0.01_r8
       end if




        if (istp.eq.ecm_step) then

           permyc(p,istp)      = perecm(ivt(p))
           !kc_active(p,istp)   = ekc_active(ivt(p))
           !kn_active(p,istp)   = ekn_active(ivt(p))
 
          if(ivt(p).eq. 3.or. ivt(p).eq.6)then 
             !Allen et al (2020) values 
             !kc_active(p,istp)   = 0.015_r8
             !kn_active(p,istp)   = 0.0025_r8
             !CLM5 values 
             kc_active(p,istp)   = 0.036_r8
             kn_active(p,istp)   = 0.006_r8
           else if(ivt(p).eq.14 .or. ivt(p).eq.17 .or. ivt(p).eq.18)then
             !Allen et al (2020) values 
             !kc_active(p,istp)   = 1.5_r8/10._r8
             !kn_active(p,istp)   = 0.25_r8/10._r8
            !CLM5 values
             kc_active(p,istp)   = 3.6_r8
             kn_active(p,istp)   = 0.6_r8
           else  
             !Allen et al (2020) values 
             !kc_active(p,istp)   = 0.15_r8
             !kn_active(p,istp)   = 0.025_r8
             !CLM5 values 
             kc_active(p,istp)   = 0.36_r8
             kn_active(p,istp)   = 0.06_r8
           end if
 
         if(use_funp)then               
          if(ivt(p).eq. 3.or. ivt(p).eq.6)then 
              kcp_active(p,istp)  = (1.0_r8/10._r8)/scalex
              kp_active(p,istp)   = (0.05_r8/10._r8)/scalex
           else if(ivt(p).eq.14 .or. ivt(p).eq.17 .or. ivt(p).eq.18)then
              kcp_active(p,istp)  = (1.0_r8*1._r8)/scalex
              kp_active(p,istp)   = (0.05_r8*1._r8)/scalex
           else  
              !kcp_active(p,istp)  = ekcp_active(ivt(p))
              !kp_active(p,istp)   = ekp_active(ivt(p))
              kcp_active(p,istp)  = (1.0_r8)/scalex
              kp_active(p,istp)   = (0.05_r8)/scalex
           end if
         end if

        else
           permyc(p,istp)      = 1._r8 - perecm(ivt(p))
           !kc_active(p,istp)   = akc_active(ivt(p))
           !kn_active(p,istp)   = akn_active(ivt(p))
           if(ivt(p).eq.6)then 
            !Allen et al (2020) values 
             !kc_active(p,istp)   = 0.0025_r8
             !kn_active(p,istp)   = 0.0050_r8
             !CLM5 values 
             kc_active(p,istp)   = 0.006_r8
             kn_active(p,istp)   = 0.012_r8
           else if(ivt(p).eq.14 .or. ivt(p).eq.17 .or. ivt(p).eq.18)then
            !Allen et al (2020) values 
             !kc_active(p,istp)   = 0.25_r8/10._r8
             !kn_active(p,istp)   = 0.50_r8/10._r8
             !CLM5 values 
             kc_active(p,istp)   = 0.6_r8
             kn_active(p,istp)   = 1.2_r8
           else  
             !Allen et al (2020) values 
             !kc_active(p,istp)   = 0.025_r8
             !kn_active(p,istp)   = 0.050_r8
             !CLM5 values 
             kc_active(p,istp)   = 0.06_r8
             kn_active(p,istp)   = 0.12_r8
           end if

         if(use_funp)then
           if(ivt(p).eq. 3.or. ivt(p).eq.6)then 
              kcp_active(p,istp)  = (0.5_r8/10._r8)/scalex
              kp_active(p,istp)   = (0.1_r8/10._r8)/scalex
           else if(ivt(p).eq.14 .or. ivt(p).eq.17 .or. ivt(p).eq.18)then
              kcp_active(p,istp)  = (0.5_r8*1._r8)/scalex
              kp_active(p,istp)   = (0.1_r8*1._r8)/scalex
           else
              !kcp_active(p,istp)  = akcp_active(ivt(p))
              !kp_active(p,istp)   = akp_active(ivt(p))
              kcp_active(p,istp)  = (0.5_r8)/scalex
              kp_active(p,istp)   =  (0.1_r8)/scalex
           end if
        end if
       end if


        if(leafc(p)>0.0_r8)then
           ! N available in leaf which fell off in this timestep. Same fraction loss as C.    
           litterfall_c_step(p,istp)         =   dt * permyc(p,istp) * leafc_to_litter_fun(p) 
           litterfall_n_step(p,istp)         =   dt * permyc(p,istp) * leafn(p) * leafc_to_litter_fun(p)/leafc(p)
           if (use_funp) then
              litterfall_c_step_p(p,istp)         =   dt * permyc(p,istp) * leafc_to_litter_funp(p)
              litterfall_p_step(p,istp)         =   dt * permyc(p,istp) * leafp(p) * leafc_to_litter_funp(p)/leafc(p)
           endif 
        endif 

        if (season_decid(ivt(p)) == 1._r8.or.stress_decid(ivt(p)) == 1._r8) then
          if (offset_flag(p) .ne. 1._r8) then
            litterfall_n_step(p,istp) = 0.0_r8      
            litterfall_c_step(p,istp) = 0.0_r8 
            if(use_funp)then
              litterfall_c_step_p(p,istp) = 0.0_r8
              litterfall_p_step(p,istp) = 0.0_r8 
            endif  
          endif
        endif

     end do
  end do     
      
  do j = 1, nlevdecomp
     do fp = 1,num_soilp        ! PFT Starts
       p = filter_soilp(fp)
       c = veg_pp%column(p)
       sminn_no3_layer(c,j)= smin_no3_to_plant_vr(c,j) * dzsoi_decomp(j) * dt
       sminn_nh4_layer(c,j)= smin_nh4_to_plant_vr(c,j) * dzsoi_decomp(j) * dt
       if(use_funp)then
          sminp_pox_layer(c,j)= sminp_to_plant_vr(c,j) * dzsoi_decomp(j) * dt 
       end if 
       if (h2osoi_liq(c,j) < smallValue) then
          sminn_no3_layer(c,j) = 0._r8
          sminn_nh4_layer(c,j) = 0._r8
       if(use_funp)then
          sminp_pox_layer(c,j) = 0._r8 
       end if
       end if
       sminn_no3_layer(c,j)    = max(sminn_no3_layer(c,j),0._r8)
       sminn_nh4_layer(c,j)    = max(sminn_nh4_layer(c,j),0._r8)
       if(use_funp)then
          sminp_pox_layer(c,j)    = max(sminp_pox_layer(c,j),0._r8) 
       end if
       if (h2osoi_liq(c,j) > smallValue) then
          sminn_no3_conc(c,j)  = sminn_no3_layer(c,j) / (h2osoi_liq(c,j) * 1000._r8) ! (gN/m2)/(gH2O/m2) (coverted from
          !  kg2g)
          sminn_nh4_conc(c,j)  = sminn_nh4_layer(c,j) / (h2osoi_liq(c,j) * 1000._r8) ! (gN/m2)/(gH2O/m2) (coverted from
          !  kg2g)
       if(use_funp)then
          sminp_pox_conc(c,j)  = sminp_pox_layer(c,j) / (h2osoi_liq(c,j) * 1000._r8) ! (gP/m2)/(gH2O/m2) (coverted from
          !  kg2g)
       end if

       else
          sminn_no3_conc(c,j)  = 0._r8
          sminn_nh4_conc(c,j)  = 0._r8
       if(use_funp)then
          sminp_pox_conc(c,j)  = 0._r8
       end if

       end if
     end do
  end do

  do istp = 1, nstp
     do j = 1, nlevdecomp
        do fp = 1,num_soilp        ! PFT Starts
           p = filter_soilp(fp)
           c = veg_pp%column(p)

           sminn_no3_layer_step(p,j,istp)  =   sminn_no3_layer(c,j) * permyc(p,istp)
           sminn_nh4_layer_step(p,j,istp)  =   sminn_nh4_layer(c,j) * permyc(p,istp)
           sminn_no3_conc_step(p,j,istp)   =   sminn_no3_conc(c,j)  * permyc(p,istp)
           sminn_nh4_conc_step(p,j,istp)   =   sminn_nh4_conc(c,j)  * permyc(p,istp)

       if(use_funp)then
          sminp_pox_layer_step(p,j,istp)  =   sminp_pox_layer(c,j) * permyc(p,istp)
          sminp_pox_conc_step(p,j,istp)   =   sminp_pox_conc(c,j)  * permyc(p,istp)
       end if
        end do
     end do
  end do
  call t_stopf('CNFUNcalcs1')

  call t_startf('CNFUNzeroarrays2')
  do fp = 1,num_soilp        ! PFT Starts
     p = filter_soilp(fp)
     n_passive_acc(p)                = 0._r8
     n_fix_acc_total(p)              = 0._r8
     n_retrans_acc_total(p)          = 0._r8
     npp_fix_acc_total(p)            = 0._r8
     n_nonmyc_no3_retrans_total(p)   = 0._r8
     n_nonmyc_nh4_retrans_total(p)   = 0._r8
     npp_retrans_acc_total(p)        = 0._r8
     n_am_no3_acc(p)                 = 0._r8
     n_am_nh4_acc(p)                 = 0._r8
     n_am_no3_retrans(p)             = 0._r8
     n_am_nh4_retrans(p)             = 0._r8
     n_ecm_no3_acc(p)                = 0._r8
     n_ecm_nh4_acc(p)                = 0._r8
     n_ecm_no3_retrans(p)            = 0._r8
     n_ecm_nh4_retrans(p)            = 0._r8
     n_active_no3_acc_total(p)       = 0._r8 
     n_active_nh4_acc_total(p)       = 0._r8
     n_active_no3_retrans_total(p)   = 0._r8 
     n_active_nh4_retrans_total(p)   = 0._r8
     n_nonmyc_no3_acc_total(p)       = 0._r8
     n_nonmyc_nh4_acc_total(p)       = 0._r8
     npp_active_no3_acc_total(p)     = 0._r8
     npp_active_nh4_acc_total(p)     = 0._r8
     npp_active_no3_retrans_total(p) = 0._r8
     npp_active_nh4_retrans_total(p) = 0._r8
     npp_nonmyc_no3_acc_total(p)     = 0._r8
     npp_nonmyc_nh4_acc_total(p)     = 0._r8
     npp_nonmyc_no3_retrans_total(p) = 0._r8
     npp_nonmyc_nh4_retrans_total(p) = 0._r8
     free_Nretrans(p)                = 0._r8

     if(use_funp)then
       p_passive_acc(p)                = 0._r8
       p_retrans_acc_total(p)          = 0._r8
       p_nonmyc_pox_retrans_total(p)   = 0._r8
       npp_retrans_p_acc_total(p)      = 0._r8
       p_am_pox_acc(p)                 = 0._r8
       p_am_pox_retrans(p)             = 0._r8
       p_ecm_pox_acc(p)                = 0._r8
       p_ecm_pox_retrans(p)            = 0._r8
       p_active_pox_acc_total(p)       = 0._r8 
       p_active_pox_retrans_total(p)   = 0._r8 
       p_nonmyc_pox_acc_total(p)       = 0._r8
       npp_active_pox_acc_total(p)     = 0._r8
       npp_active_pox_retrans_total(p) = 0._r8
       npp_nonmyc_pox_acc_total(p)     = 0._r8
       npp_nonmyc_pox_retrans_total(p) = 0._r8
       free_Pretrans(p)                = 0._r8
     end if
  end do

  do j = 1, nlevdecomp
     do fp = 1,num_soilp        ! PFT Starts
        p = filter_soilp(fp)
        n_passive_no3_vr(p,j)           = 0._r8
        n_passive_nh4_vr(p,j)           = 0._r8
        n_active_no3_vr(p,j)            = 0._r8
        n_nonmyc_no3_vr(p,j)            = 0._r8
        n_active_nh4_vr(p,j)            = 0._r8
        n_nonmyc_nh4_vr(p,j)            = 0._r8

        if(use_funp)then
          p_passive_pox_vr(p,j)         = 0._r8
          p_active_pox_vr(p,j)          = 0._r8
          p_nonmyc_pox_vr(p,j)          = 0._r8
        end if

     end do
  end do
  do istp = 1, nstp
     do fp = 1,num_soilp        ! PFT Starts
        p = filter_soilp(fp)
        n_passive_step(p,istp)          = 0._r8
        n_fix_acc(p,istp)               = 0._r8
        n_retrans_acc(p,istp)           = 0._r8
        npp_fix_acc(p,istp)             = 0._r8
        npp_retrans_acc(p,istp)         = 0._r8
        n_active_no3_acc(p,istp)        = 0._r8   
        n_active_nh4_acc(p,istp)        = 0._r8  
        n_active_no3_retrans(p,istp)    = 0._r8
        n_active_nh4_retrans(p,istp)    = 0._r8
        n_nonmyc_no3_acc(p,istp)        = 0._r8  
        n_nonmyc_nh4_acc(p,istp)        = 0._r8  
        n_nonmyc_no3_retrans(p,istp)    = 0._r8
        n_nonmyc_nh4_retrans(p,istp)    = 0._r8
        npp_active_no3_acc(p,istp)      = 0._r8
        npp_active_nh4_acc(p,istp)      = 0._r8
        npp_active_no3_retrans(p,istp)  = 0._r8
        npp_active_nh4_retrans(p,istp)  = 0._r8
        npp_nonmyc_no3_acc(p,istp)      = 0._r8
        npp_nonmyc_nh4_acc(p,istp)      = 0._r8
        npp_nonmyc_no3_retrans(p,istp)  = 0._r8
        npp_nonmyc_nh4_retrans(p,istp)  = 0._r8

        if(use_funp)then
          p_passive_step(p,istp)          = 0._r8
          p_retrans_acc(p,istp)           = 0._r8
          npp_retrans_p_acc(p,istp)       = 0._r8
          p_active_pox_acc(p,istp)        = 0._r8    
          p_active_pox_retrans(p,istp)    = 0._r8
          p_nonmyc_pox_acc(p,istp)        = 0._r8    
          p_nonmyc_pox_retrans(p,istp)    = 0._r8
          npp_active_pox_acc(p,istp)      = 0._r8
          npp_active_pox_retrans(p,istp)  = 0._r8
          npp_nonmyc_pox_acc(p,istp)      = 0._r8
          npp_nonmyc_pox_retrans(p,istp)  = 0._r8
          burned_off_carbon_p             = 0._r8 
        end if
     end do
  end do

  burned_off_carbon               = 0._r8 
  call t_stopf('CNFUNzeroarrays2')

  call t_startf('CNFUNcalcs')

pft:do fp = 1,num_soilp        ! PFT Starts
      p = filter_soilp(fp)
      c = veg_pp%column(p)
      excess_carbon_acc              = 0.0_r8
      burned_off_carbon              = 0.0_r8
     
      sminn_to_plant_fun_nh4_vr(p,:) = 0._r8
      sminn_to_plant_fun_no3_vr(p,:) = 0._r8  

      if(use_funp)then
          excess_carbon_acc_p        = 0.0_r8
          burned_off_carbon_p        = 0.0_r8
          sminp_to_plant_fun_vr(p,:) = 0._r8
      end if    
     
      ! I have turned off this r etranslocation functionality for now. To
      !  be rolled back in to a new version later on once the rest of
      !   th
      ! mode is working OK. RF

      if (season_decid(ivt(p)) == 1._r8.or.stress_decid(ivt(p)) == 1._r8) then
         if (onset_flag(p) == 1._r8) then
            leafc_storage_xfer_acc(p) = leafc_storage_xfer_acc(p) + leafc_storage_to_xfer(p) * dt
            leafn_storage_xfer_acc(p) = leafn_storage_xfer_acc(p) + leafn_storage_to_xfer(p) * dt
         if(use_funp)then
          leafp_storage_xfer_acc(p) = leafp_storage_xfer_acc(p) + leafp_storage_to_xfer(p) * dt
         end if 
         end if
         if (offset_flag(p) == 1._r8) then
            storage_cdemand(p)        = leafc_storage(p)          / (ndays_off * steppday)
            storage_ndemand(p)        = leafn_storage_xfer_acc(p) / (ndays_off * steppday)
            storage_ndemand(p)        = max(storage_ndemand(p),0._r8)
        if(use_funp)then
          storage_pdemand(p)        = leafp_storage_xfer_acc(p) / (ndays_off * steppday)
          storage_pdemand(p)        = max(storage_pdemand(p),0._r8)
        end if

         else
            storage_cdemand(p)        = 0._r8    
            storage_ndemand(p)        = 0._r8  
        if(use_funp)then
            storage_pdemand(p)        = 0._r8
        end if 
         end if
      else
          storage_cdemand(p)          = 0._r8
          storage_ndemand(p)          = 0._r8 
        if(use_funp)then
            storage_pdemand(p)        = 0._r8
        end if 
      end if   ! end for deciduous

     
      !---------How much carbon is provided, to be used for either growth
      ! or Nitrogen uptake?-------------------
      if(use_funp)then
      !availc_pool(p)            =  availc(p)        *  dt * (1._r8 - plantCN(p)/plantCP(p))
      !availc_pool_p(p)          =  scale_availc * availc(p) *  dt * (plantCN(p)/plantCP(p)) 
      availc_pool(p)            =  availc(p)        *  dt * (plant_ndemand(p)*plantCN(p)/(plant_ndemand(p)*plantCN(p) + plant_pdemand(p)*plantCP(p)))
      availc_pool_p(p)          =  availc(p) *  dt * (plant_pdemand(p)*plantCP(p)/(plant_ndemand(p)*plantCN(p) + plant_pdemand(p)*plantCP(p)))
       !write(iulog,*) 'N req =',100.0_r8*(plant_ndemand(p)*plantCN(p)/(plant_ndemand(p)*plantCN(p) + plant_pdemand(p)*plantCP(p))), &
       !               'P req =',100.0_r8*(plant_pdemand(p)*plantCP(p)/(plant_ndemand(p)*plantCN(p) + plant_pdemand(p)*plantCP(p)))
      else  
      availc_pool(p)            =  availc(p)        *  dt 
      end if

      if(use_funp)then
        !grperc_n(p) = grperc(ivt(p)) * (1._r8 - plantCN(p)/plantCP(p))
        !grperc_p(p) = grperc(ivt(p)) * (plantCN(p)/plantCP(p))  
        grperc_n(p) = grperc(ivt(p)) * (plant_ndemand(p)*plantCN(p)/(plant_ndemand(p)*plantCN(p) + plant_pdemand(p)*plantCP(p)))
        grperc_p(p) = grperc(ivt(p)) * (plant_pdemand(p)*plantCP(p)/(plant_ndemand(p)*plantCN(p) + plant_pdemand(p)*plantCP(p)))  
      else
        grperc_n(p) = grperc(ivt(p)) 
      end if  

      if (availc_pool(p) > 0._r8) then
         do j = 1, nlevdecomp
            rootc_dens(p,j)     =  crootfr(p,j) * rootC(p)
         end do
      end if

      plant_ndemand_pool(p)     =  plant_ndemand(p) *  dt
      plant_ndemand_pool(p)     =  max(plant_ndemand_pool(p),0._r8)
      plant_ndemand_retrans(p)  =  storage_ndemand(p)

      if(use_funp)then
         plant_pdemand_pool(p)     =  plant_pdemand(p) *  dt
         plant_pdemand_pool(p)     =  max(plant_pdemand_pool(p),0._r8)
         plant_pdemand_retrans(p)  =  storage_pdemand(p)
      end if 

      !--------------------------------------------------------------------
      !----------
stp:  do istp = ecm_step, am_step        ! TWO STEPS
         retrans_limit1              = 0._r8
         dn                          = 0._r8
         dnpp                        = 0._r8
      
         ! zero out all of the fluxes that get accumulated accross ISTP 
         sminn_no3_diff              = 0._r8
         sminn_nh4_diff              = 0._r8
         active_no3_limit1           = 0._r8
         active_nh4_limit1           = 0._r8

         
         n_from_active_no3(:)        = 0.0_r8
         n_from_active_nh4(:)        = 0.0_r8
         n_from_nonmyc_no3(:)        = 0.0_r8
         n_from_nonmyc_nh4(:)        = 0.0_r8
         n_from_fixation(:)          = 0.0_r8
         n_from_retrans(:)           = 0.0_r8
         
         n_active_no3_acc(p,istp)    = 0.0_r8
         n_active_nh4_acc(p,istp)    = 0.0_r8
         n_nonmyc_no3_acc(p,istp)    = 0.0_r8
         n_nonmyc_nh4_acc(p,istp)    = 0.0_r8
         n_fix_acc(p,istp)           = 0.0_r8
         n_retrans_acc(p,istp)       = 0.0_r8
         free_nretrans_acc(p,istp)   = 0.0_r8
 
         npp_active_no3_acc(p,istp)  = 0.0_r8
         npp_active_nh4_acc(p,istp)  = 0.0_r8
         npp_nonmyc_no3_acc(p,istp)  = 0.0_r8
         npp_nonmyc_no3_acc(p,istp)  = 0.0_r8
         npp_fix_acc(p,istp)         = 0.0_r8
         npp_retrans_acc(p,istp)     = 0.0_r8
         
         npp_to_active_no3(:)        = 0.0_r8
         npp_to_active_nh4(:)        = 0.0_r8
         npp_to_nonmyc_no3(:)        = 0.0_r8
         npp_to_nonmyc_nh4(:)        = 0.0_r8
         npp_to_fixation(:)          = 0.0_r8
         npp_to_retrans(:)           = 0.0_r8
     
  
      
         unmetDemand              = .TRUE.
         plant_ndemand_pool_step(p,istp)   = plant_ndemand_pool(p)    * permyc(p,istp) 
        
         npp_remaining(p,istp)             = availc_pool(p)           * permyc(p,istp)  

    
    !write(iulog,*) 'Fixer fraction', FUN_fracfixers(ivt(p)), &
    !                   'Soil N', smin_vr_no3(c,:)+smin_vr_nh4(c,:), &
    !                          'Soil P', solutionp_vr(c,:), &
    !                          'Fine Root Biomass', frootc(p), &
    !                          'Frac Root nlevgrd', crootfr(p,:), &      
    !                          'leaf N', leafn(p), &
    !                          'leaf P', leafp(p), &
    !                          'NPP0', availc(p), & !(?) 
    !                          'plantcn', leafcn(ivt(p)), &
    !                          'plantcp', leafcp(ivt(p)), &
    !                          'plantnp', leafcp(ivt(p))/leafcn(ivt(p)), &
    !                          'Soil water depth', h2osoi_liq(c,1), & 
    !                          'Soil T', t_soisno(c,1), & 
    !                          'ET', qflx_tran_veg(p), & !NaN
    !                          'c3psn', veg_vp%c3psn, &
    !                          'ivt(p)', ivt(p), &
    !                         'perECM', perecm(ivt(p))
         
  
         ! if (plant_ndemand_pool_step(p,istp) .gt. 0._r8) then   !
            !  plant_ndemand_pool_step > 0.0
            
            do j = 1, nlevdecomp
               tc_soisno(c,j)          = t_soisno(c,j)  -   tfrz
               ! running mean soil temperature only calculated for single soil layer
               tc_soila10(c)           = soila10(c)     -   tfrz
               !tc_soila10(c)          = t_soisno(c,3)  -   tfrz

               if(veg_vp%c3psn(veg_pp%itype(p)).eq.1)then
                 fixer=1
               else
                 fixer=0
               endif
               costNit(j,icostFix)     = fun_cost_fix(fixer,a_fix(ivt(p)),b_fix(ivt(p))&
               ,c_fix(ivt(p)) ,big_cost,crootfr(p,j),s_fix(ivt(p)),tc_soisno(c,j))

               ! Bytnerowicz no acclimation calculation
               !costNit(j,icostFix) = fun_cost_fix_Bytnerowicz_noAcc(fixer,Tmin_fix,Topt_fix&
               !,Tmax_fix ,big_cost,crootfr(p,j),s_fix(ivt(p)),tc_soisno(c,j))


               ! Bytnerowicz acclimation calculation
               !costNit(j,icostFix) = fun_cost_fix_Bytnerowicz_Acc(fixer,Tmin_fix,Topt_fix&
               !,Tmax_fix ,big_cost,crootfr(p,j),s_fix(ivt(p)),tc_soila10(c))



            end do
            cost_fix(p,1:nlevdecomp)      = costNit(:,icostFix)

         if(use_funp)then
         retrans_limit2              = 0._r8
         dp                          = 0._r8
         dnpp_p                      = 0._r8
      
         ! zero out all of the fluxes that get accumulated accross ISTP 
         sminp_pox_diff              = 0._r8
         active_pox_limit2           = 0._r8
         
         p_from_active_pox(:)        = 0.0_r8
         p_from_nonmyc_pox(:)        = 0.0_r8
         p_from_retrans(:)           = 0.0_r8
         
         p_active_pox_acc(p,istp)    = 0.0_r8
         p_nonmyc_pox_acc(p,istp)    = 0.0_r8
         p_retrans_acc(p,istp)       = 0.0_r8
         free_pretrans_acc(p,istp)   = 0.0_r8
 
         npp_active_pox_acc(p,istp)  = 0.0_r8
         npp_nonmyc_pox_acc(p,istp)  = 0.0_r8
         npp_retrans_p_acc(p,istp)   = 0.0_r8
         
         npp_to_active_pox(:)        = 0.0_r8
         npp_to_nonmyc_pox(:)        = 0.0_r8
         npp_to_retrans_p(:)         = 0.0_r8
     
  
      
         unmetDemandP              = .TRUE.
         plant_pdemand_pool_step(p,istp)   = plant_pdemand_pool(p)    * permyc(p,istp) 
         npp_remaining_p(p,istp)           = availc_pool_p(p)         * permyc(p,istp) 
         end if
            
             
            !--------------------------------------------------------------------
            !------------
            !         If passive uptake is insufficient, consider fixation,
            !          mycorrhizal 
            !         non-mycorrhizal, storage, and retranslocation.
            !--------------------------------------------------------------------
            !------------
            !--------------------------------------------------------------------
            !------------
            !          Costs of active uptake.
            !--------------------------------------------------------------------
            !------------
            !------Mycorrhizal Uptake Cost-----------------!
            do j = 1,nlevdecomp
               rootc_dens_step            = rootc_dens(p,j) *  permyc(p,istp)
               costNit(j,icostActiveNO3)  = fun_cost_active(sminn_no3_layer_step(p,j,istp) &
               ,big_cost,kc_active(p,istp),kn_active(p,istp) ,rootc_dens_step,crootfr(p,j),smallValue)
               costNit(j,icostActiveNH4)  = fun_cost_active(sminn_nh4_layer_step(p,j,istp) &
               ,big_cost,kc_active(p,istp),kn_active(p,istp) ,rootc_dens_step,crootfr(p,j),smallValue)
               if(use_funp)then
                  costPho(j,icostActivePOX)  = fun_cost_active(sminp_pox_layer_step(p,j,istp) &
               ,big_cost,kcp_active(p,istp),kp_active(p,istp) ,rootc_dens_step,crootfr(p,j),smallValue)
               end if            

            end do
            cost_active_no3(p,1:nlevdecomp)  = costNit(:,icostActiveNO3) 
            cost_active_nh4(p,1:nlevdecomp)  = costNit(:,icostActiveNH4)
            if(use_funp)then
               cost_active_pox(p,1:nlevdecomp)  = costPho(:,icostActivePOX)
            end if  
            

            !------Non-mycorrhizal Uptake Cost-------------!
            do j = 1,nlevdecomp
               rootc_dens_step             = rootc_dens(p,j)  *  permyc(p,istp)
 
           if(ivt(p).eq.6)then 
             !Allen et al (2020) values 
             !kc_nonmyc(ivt(p))   = 0.15_r8/10._r8
             !kn_nonmyc(ivt(p))   = 0.15_r8/10._r8 
            !CLM5 values 
             kc_nonmyc(ivt(p))   = 0.0012_r8
             kn_nonmyc(ivt(p))   = 0.072_r8
           else if(ivt(p).eq.3)then
             !Allen et al (2020) values 
             !kc_nonmyc(ivt(p))   = 0.15_r8
             !kn_nonmyc(ivt(p))   = 0.15_r8/10._r8 
            !CLM5 values 
             kc_nonmyc(ivt(p))   = 0.0012_r8
             kn_nonmyc(ivt(p))   = 0.72_r8
           else if(ivt(p).eq.14 .or. ivt(p).eq.17 .or. ivt(p).eq.18)then
             !Allen et al (2020) values 
             !kc_nonmyc(ivt(p))   = 0.15_r8*1._r8
             !kn_nonmyc(ivt(p))   = 0.15_r8*1._r8
             !CLM5 values 
             kc_nonmyc(ivt(p))   = 0.12_r8
             kn_nonmyc(ivt(p))   = 7.2_r8
           else  
             !Allen et al (2020) values
             !kc_nonmyc(ivt(p))   = 0.15_r8
             !kn_nonmyc(ivt(p))   = 0.15_r8 
             !kc_nonmyc(ivt(p))   = 0.01_r8
             !kn_nonmyc(ivt(p))   = 0.90_r8
             !CLM5 values 
             kc_nonmyc(ivt(p))   = 0.012_r8
             kn_nonmyc(ivt(p))   = 0.72_r8
           end if

               costNit(j,icostnonmyc_no3)   = fun_cost_nonmyc(sminn_no3_layer_step(p,j,istp) &
               ,big_cost,kc_nonmyc(ivt(p)),kn_nonmyc(ivt(p)),rootc_dens_step,crootfr(p,j),smallValue)
               costNit(j,icostnonmyc_nh4)   = fun_cost_nonmyc(sminn_nh4_layer_step(p,j,istp) &
               ,big_cost,kc_nonmyc(ivt(p)),kn_nonmyc(ivt(p)),rootc_dens_step,crootfr(p,j),smallValue)

          if(use_funp)then
           if(ivt(p).eq.6)then 
             kcp_nonmyc(ivt(p))  = (0.03_r8/10._r8)/scalex
             kp_nonmyc(ivt(p))   = (0.08_r8/10._r8)/scalex
           else if(ivt(p).eq.3)then
             kcp_nonmyc(ivt(p))  = (0.03_r8)/scalex
             kp_nonmyc(ivt(p))   = (0.08_r8/10._r8)/scalex
           else if(ivt(p).eq.14 .or. ivt(p).eq.17 .or. ivt(p).eq.18)then
             kcp_nonmyc(ivt(p))  = (0.03_r8*1._r8)/scalex
             kp_nonmyc(ivt(p))   = (0.08_r8*1._r8)/scalex
           else  
             !Allen et al (2020) values 
             kcp_nonmyc(ivt(p))  = (0.03_r8)/scalex
             kp_nonmyc(ivt(p))   = (0.08_r8)/scalex
           end if
   
                costPho(j,icostnonmyc_pox)  = fun_cost_nonmyc(sminp_pox_layer_step(p,j,istp) &
               ,big_cost,kcp_nonmyc(ivt(p)),kp_nonmyc(ivt(p)) ,rootc_dens_step,crootfr(p,j),smallValue)
              end if   
           end do

            cost_nonmyc_no3(p,1:nlevdecomp)   = costNit(:,icostnonmyc_no3)
            cost_nonmyc_nh4(p,1:nlevdecomp)   = costNit(:,icostnonmyc_nh4)
            if(use_funp)then
              cost_nonmyc_pox(p,1:nlevdecomp)   = costPho(:,icostnonmyc_pox)
            end if  

            ! Remove C required to pair with N from passive uptake
            !  from the available pool. 
            npp_remaining(p,istp)  =   npp_remaining(p,istp) - n_passive_step(p,istp)*plantCN(p)

            if(use_funp)then
            ! Remove C required to pair with P from passive uptake
            !  from the available pool and the one used to acquire N
              npp_remaining_p(p,istp)  =   npp_remaining_p(p,istp) - p_passive_step(p,istp)*plantCP(p) 
            end if


              
fix_loop:   do FIX =plants_are_fixing, plants_not_fixing !loop around percentages of fixers and non
               ! fixers, with differnt costs. 

        !FUN_fracfixers = (/0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, &
        !                   0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, & 
        !                   0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, 0.25_r8, &
        !                   0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8, 0.0_r8, &
        !                   0.0_r8, 0.0_r8, 0.0_r8, 1.0_r8, 1.0_r8, 1.0_r8/)

       if(ivt(p).eq.0)then
         FUN_fracfixers(ivt(p)) = 1.0_r8
       else if(ivt(p).le.14 )then
         FUN_fracfixers(ivt(p)) = 0.25_r8
       else if(ivt(p).ge.23)then
         FUN_fracfixers(ivt(p)) = 1.0_r8
       else
         FUN_fracfixers(ivt(p)) = 0.0_r8
       end if

           !write(iulog,*) 'ivt(p)', ivt(p), &
           !       'FUN_fracfixers(ivt(p))',FUN_fracfixers(ivt(p))


               if(FIX==plants_are_fixing)then ! How much of the carbon in this PFT can in principle be used for fixation? 
                 ! This is analagous to fixing the % of fixers for a given PFT - may not be realistic in the long run
                 ! but prevents wholesale switching to fixer dominance during e.g. CO2 fertilization.  
                 fixerfrac = FUN_fracfixers(ivt(p))
                 fixerfrac_p = 0.0_r8
               else
                 fixerfrac = 1.0_r8 - FUN_fracfixers(ivt(p))
                 fixerfrac_p = 1.0_r8
               endif 
               npp_to_spend = npp_remaining(p,istp)  * fixerfrac !put parameter here.



               n_from_active_no3(1:nlevdecomp) = 0._r8
               n_from_active_nh4(1:nlevdecomp) = 0._r8
               n_from_nonmyc_no3(1:nlevdecomp) = 0._r8
               n_from_nonmyc_nh4(1:nlevdecomp) = 0._r8

            if(use_funp)then
               npp_to_spend_p = npp_remaining_p(p,istp)  * fixerfrac_p !put ??? parameter here.
               p_from_active_pox(1:nlevdecomp) = 0._r8
               p_from_nonmyc_pox(1:nlevdecomp) = 0._r8
            end if

               !--------------------------------------------------------------------
               !-----------
               !           Calculate Integrated Resistance OF WHOLE SOIL COLUMN
               !--------------------------------------------------------------------
               !----------- 

               sum_n_acquired      = 0.0_r8
               total_N_conductance = 0.0_r8
            if(use_funp)then
               sum_p_acquired      = 0.0_r8
               total_P_conductance = 0.0_r8
            end if

               do j = 1, nlevdecomp
                  !----------!
                  ! Method changed from FUN-resistors method to a method which 
                  ! allocates fluxs based on conductance. rosief
                  !----------!
             
                  ! Sum the conductances             
                  total_N_conductance  = total_N_conductance + 1._r8/ &
                                         cost_active_no3(p,j) + 1._r8/cost_active_nh4(p,j) &
                                         + 1._r8/cost_nonmyc_no3(p,j)      &
                                         + 1._r8/cost_nonmyc_nh4(p,j) 
            if(use_funp)then
               total_P_conductance  = total_P_conductance + 1._r8/ &
                                         cost_active_pox(p,j) &
                                       + 1._r8/cost_nonmyc_pox(p,j)
            end if

                  if(FIX==plants_are_fixing)then
                      total_N_conductance  = total_N_conductance  + 1.0_r8 * 1._r8/cost_fix(p,j)
                  end if 
                      
                end do 
             
                do j = 1, nlevdecomp     
                  ! Calculate npp allocation to pathways proportional to their exchange rate (N/C) 
                
                  npp_frac_to_active_nh4(j) = (1._r8/cost_active_nh4(p,j)) / total_N_conductance
                  npp_frac_to_nonmyc_nh4(j) = (1._r8/cost_nonmyc_nh4(p,j)) / total_N_conductance
                  npp_frac_to_active_no3(j) = (1._r8/cost_active_no3(p,j)) / total_N_conductance
                  npp_frac_to_nonmyc_no3(j) = (1._r8/cost_nonmyc_no3(p,j)) / total_N_conductance
                  if(use_funp)then
                     npp_frac_to_active_pox(j) = (1._r8/cost_active_pox(p,j)) / total_P_conductance
                     npp_frac_to_nonmyc_pox(j) = (1._r8/cost_nonmyc_pox(p,j)) / total_P_conductance
                  end if

                  if(FIX==plants_are_fixing)then
                    npp_frac_to_fixation(j)   = (1.0_r8 * 1._r8/cost_fix(p,j)) / total_N_conductance
                  else
                    npp_frac_to_fixation(j)   = 0.0_r8 
                  end if
                     
                  ! Calculate hypothetical N uptake from each source   
                  if(FIX==plants_are_fixing)then
                    n_exch_fixation(j)   = npp_frac_to_fixation(j)   / cost_fix(p,j)
                  else
                    n_exch_fixation(j)   = 0.0_r8 
                  end if                   
              
                  n_exch_active_nh4(j) = npp_frac_to_active_nh4(j) / cost_active_nh4(p,j) 
                  n_exch_nonmyc_nh4(j) = npp_frac_to_nonmyc_nh4(j) / cost_nonmyc_nh4(p,j) 
                  n_exch_active_no3(j) = npp_frac_to_active_no3(j) / cost_active_no3(p,j) 
                  n_exch_nonmyc_no3(j) = npp_frac_to_nonmyc_no3(j) / cost_nonmyc_no3(p,j) 

                  if(use_funp)then
                     p_exch_active_pox(j) = npp_frac_to_active_pox(j) / cost_active_pox(p,j) 
                     p_exch_nonmyc_pox(j) = npp_frac_to_nonmyc_pox(j) / cost_nonmyc_pox(p,j) 
                  end if
               
                  ! Total N aquired from one unit of carbon  (N/C)
                  sum_n_acquired        =  sum_n_acquired  + n_exch_active_nh4(j) +&
                                        n_exch_nonmyc_nh4(j)+ n_exch_active_no3(j) + n_exch_nonmyc_no3(j)

                  if(use_funp)then
                  ! Total P aquired from one unit of carbon  (P/C)
                  sum_p_acquired        =  sum_p_acquired  + p_exch_active_pox(j) +&
                                        p_exch_nonmyc_pox(j)
                  end if
                                          
                  if(FIX==plants_are_fixing)then
                    sum_n_acquired= sum_n_acquired +  n_exch_fixation(j)
                  end if 
                                                                           
               end do !nlevdecomp
            
               total_N_resistance = 1.0_r8/sum_n_acquired
               if(use_funp)then
                  total_P_resistance = 1.0_r8/sum_p_acquired 
               end if

               !-------------------------------------------------------------------------------
               !           Calculate appropriate degree of retranslocation
               !-------------------------------------------------------------------------------
      
               if(leafc(p).gt.0.0_r8.and.litterfall_n_step(p,istp)* fixerfrac>0.0_r8.and.ivt(p) <npcropmin)then
                  call fun_retranslocation(p,dt,npp_to_spend,&
                                litterfall_c_step(p,istp)* fixerfrac,&
                                litterfall_n_step(p,istp)* fixerfrac,&
                                total_n_resistance, total_c_spent_retrans,total_c_accounted_retrans, &
                                free_n_retrans,paid_for_n_retrans, leafcn(ivt(p)), & 
                                grperc_n(p), plantCN(p))

              
                                 
               else
                   total_c_accounted_retrans = 0.0_r8
                   total_c_spent_retrans     = 0.0_r8
                   total_c_accounted_retrans = 0.0_r8
                   paid_for_n_retrans        = 0.0_r8
                   free_n_retrans            = 0.0_r8

               endif
   
        if(use_funp)then    
               if(leafc(p).gt.0.0_r8.and.litterfall_p_step(p,istp)* fixerfrac_p>0.0_r8.and.ivt(p) <npcropmin)then

   
                !call fun_retranslocation(p,dt,npp_to_spend_p,&
                !                litterfall_c_step_p(p,istp)* fixerfrac_p,&
                !                litterfall_p_step(p,istp)* fixerfrac_p,&
                !                total_p_resistance, total_c_spent_retrans_p,total_c_accounted_retrans_p, &
                !                free_p_retrans,paid_for_p_retrans, leafcp(ivt(p)), & 
                !                grperc_p(p), plantCP(p))

                !write(iulog,*) 'p=',p,&
                !               'dt=',dt,&
                !               'npp_to_spend_p=',npp_to_spend_p,&
                !               'litterfall_c_step_p(p,istp)* fixerfrac_p=', litterfall_c_step_p(p,istp)* fixerfrac_p,&
                !                'litterfall_p_step(p,istp)* fixerfrac_p=',litterfall_p_step(p,istp)* fixerfrac_p,&
                !                'total_p_resistance=',total_p_resistance, &
!'total_c_spent_retrans_p=',total_c_spent_retrans_p,&

!'total_c_accounted_retrans_p=', total_c_accounted_retrans_p,&
!                                'free_p_retrans=',free_p_retrans,&
!'paid_for_p_retrans=',paid_for_p_retrans,&

! 'leafcp(ivt(p))=',leafcp(ivt(p)), & 
!                          'grperc(ivt(p))=',       grperc(ivt(p)),&
! 'plantCP(p)=', plantCP(p)

                 call fun_retranslocation_p(p,dt,npp_to_spend_p,&
                                litterfall_c_step_p(p,istp)* fixerfrac_p,&
                                litterfall_p_step(p,istp)* fixerfrac_p,&
                                total_p_resistance, total_c_spent_retrans_p,total_c_accounted_retrans_p, &
                                free_p_retrans,paid_for_p_retrans, leafcp(ivt(p)), & 
                                grperc_p(p), plantCP(p),smallValue,big_cost)
               
                 else

  
                     total_c_accounted_retrans_p = 0.0_r8
                     total_c_spent_retrans_p     = 0.0_r8
                     total_c_accounted_retrans_p = 0.0_r8
                     paid_for_p_retrans          = 0.0_r8
                     free_p_retrans              = 0.0_r8
                   end if
          end if
  
               !---------- add retrans fluxes in to total budgets. --------
               ! remove C from available pool, both directly spent and accounted for by N uptake
               total_c_spent_retrans = max(total_c_spent_retrans,0.0_r8)       
               total_c_accounted_retrans = max(total_c_accounted_retrans,0.0_r8)    
               npp_to_spend  = npp_to_spend - total_c_spent_retrans - total_c_accounted_retrans

               npp_to_spend = max(npp_to_spend,0.0_r8)  

               npp_retrans_acc(p,istp) = npp_retrans_acc(p,istp) + total_c_spent_retrans 
               ! add to to C spent pool    

               paid_for_n_retrans = max(paid_for_n_retrans,0.0_r8)                            
               n_retrans_acc(p,istp)     = n_retrans_acc(p,istp)     + paid_for_n_retrans
               free_nretrans_acc(p,istp) = free_nretrans_acc(p,istp) + free_n_retrans
               ! add N to the acquired from retrans pool 
               if(use_funp)then
               ! remove C from available pool, both directly spent and accounted for by P uptake
                  total_c_spent_retrans_p = max(total_c_spent_retrans_p,0.0_r8)       
                  total_c_accounted_retrans_p = max(total_c_accounted_retrans_p,0.0_r8)    

                 npp_to_spend_p  = npp_to_spend_p - total_c_spent_retrans_p - total_c_accounted_retrans_p 

                 npp_to_spend_p = max(npp_to_spend_p,0.0_r8)    


                 npp_retrans_p_acc(p,istp) = npp_retrans_p_acc(p,istp) + total_c_spent_retrans_p 

            
               ! add to to C spent pool
               
                paid_for_p_retrans = max(paid_for_p_retrans,0.0_r8)          

                 p_retrans_acc(p,istp)     = p_retrans_acc(p,istp)     + paid_for_p_retrans
                 free_pretrans_acc(p,istp) = free_pretrans_acc(p,istp) + free_p_retrans
               ! add P to the acquired from retrans pool 
               end if
  
            
               !-------------------------------------------------------------------------------
               !           Spend C on extracting N.
               !-------------------------------------------------------------------------------
               if (plant_ndemand_pool_step(p,istp) .gt. 0._r8) then    ! unmet demand
  
                 !if(local_use_flexiblecn)then   !(Comment FlexCN bit)
                 !    if (leafn(p) == 0.0_r8) then   ! to avoid division by zero
                 !      delta_CN = fun_cn_flex_c(ivt(p))   ! Max CN ratio over standard
                 !    else
                 !      delta_CN = (leafc(p)+leafc_storage(p))/(leafn(p)+leafn_storage(p)) - leafcn(ivt(p)) ! leaf CN ratio                                                              
                 !    end if
                     ! C used for uptake is reduced if the cost of N is very high                
                 !    frac_ideal_C_use = max(0.0_r8,1.0_r8 - (total_N_resistance-fun_cn_flex_a(ivt(p)))/fun_cn_flex_b(ivt(p)) )
                     ! then, if the plant is very much in need of N, the C used for uptake is increased accordingly.                  
                 !    if(delta_CN .gt.0.and. frac_ideal_C_use.lt.1.0)then           
                 !      frac_ideal_C_use = frac_ideal_C_use + (1.0_r8-frac_ideal_C_use)*min(1.0_r8, delta_CN/fun_cn_flex_c(ivt(p)))
                 !    end if    
                     ! If we have too much N (e.g. from free N retranslocation) then make frac_ideal_c_use even lower.    
                     ! For a CN delta of fun_cn_flex_c, then we reduce C expendiure to the minimum of 0.5. 
                     ! This seems a little intense? 
                 !    if(delta_CN.lt.0.0)then
                 !       frac_ideal_C_use = frac_ideal_C_use + 0.5_r8*(1.0_r8*delta_CN/fun_cn_flex_c(ivt(p)))
                 !    endif 
                 !    frac_ideal_C_use = max(min(1.0_r8,frac_ideal_C_use),0.5_r8) 
                     ! don't let this go above 1 or below an arbirtray minimum (to prevent zero N uptake). 
                 !else
                     frac_ideal_C_use= 1.0_r8
                 !end if (Comment FlexCN bit)
                 
               
                 excess_carbon = npp_to_spend * (1.0_r8-frac_ideal_c_use)
                 if(excess_carbon*(1.0_r8+grperc_n(p)).gt.npp_to_spend)then !prevent negative dnpp
                      excess_carbon =  npp_to_spend/(1.0_r8+grperc_n(p))
                 endif
                

                 excess_carbon_acc             = excess_carbon_acc + excess_carbon

                 ! spend less C than you have to to meet the target, thus allowing C:N ratios to rise. 
                 npp_to_spend         = npp_to_spend - excess_carbon*(1.0_r8 + grperc_n(p))
            
                 ! This is the main equation of FUN, which figures out how much C to spend on uptake to remain at the target CN ratio. 
                 ! nb. This term assumes that cost of N is constant through the timestep, because we don't have 
                 ! a concept of Michealis Menten kinetics. 
                 ! 
                 !Calculate the hypothetical amount of NPP that we should use to extract N over whole profile
                 !This calculation is based on the simulataneous solution of the uptake and extraction N balance. 
                 !It satisfies the criteria (spentC+growthC=availC AND spentC/cost=growthC/plantCN
                 !Had to add growth respiration here to balance carbon pool. 

               
                 dnpp  = npp_to_spend / ( (1.0_r8+grperc_n(p))*(plantCN(p) / total_N_resistance) + 1._r8)  
                 dnpp  = dnpp * frac_ideal_C_use
           
                 !hypothetical amount of N acquired. 
                 dn    = dnpp / total_N_resistance

                 do j = 1,nlevdecomp
                        
                     ! RF How much of this NPP carbon do we allocate to the different pathways? fraction x gC/m2/s?
                     ! Could this code now be put in a matrix? 

                     npp_to_active_nh4(j) = npp_frac_to_active_nh4(j) * dNPP
                     npp_to_nonmyc_nh4(j) = npp_frac_to_nonmyc_nh4(j) * dNPP
                     npp_to_active_no3(j) = npp_frac_to_active_no3(j) * dNPP
                     npp_to_nonmyc_no3(j) = npp_frac_to_nonmyc_no3(j) * dNPP 

                  
                     
                     if(FIX==plants_are_fixing)then
                       npp_to_fixation(j) = npp_frac_to_fixation(j) * dNPP
                     else
                       npp_to_fixation(j) = 0.0_r8
                     end if    

                     n_from_active_nh4(j) = npp_to_active_nh4(j)  / cost_active_nh4(p,j)
                     n_from_nonmyc_nh4(j) = npp_to_nonmyc_nh4(j)  / cost_nonmyc_nh4(p,j)
                     n_from_active_no3(j) = npp_to_active_no3(j)  / cost_active_no3(p,j)
                     n_from_nonmyc_no3(j) = npp_to_nonmyc_no3(j)  / cost_nonmyc_no3(p,j)

                   
                
                     if(FIX==plants_are_fixing)then
                       n_from_fixation(j) = npp_to_fixation(j)    / cost_fix(p,j)
                     else
                       n_from_fixation(j) = 0.0_r8
                     end if
                                                                     
                 end do
              
                 ! did we exceed the limits of uptake for any of these pools?
                 do j = 1,nlevdecomp    
                  
                       ! --------------------ACTIVE UPTAKE NO3 UPTAKE LIMIT------------------------!  
                       active_no3_limit1          = sminn_no3_layer_step(p,j,istp) * fixerfrac 
                  
                        ! trying to remove too much nh4 from soil. 
                        if (n_from_active_no3(j) + n_from_nonmyc_no3(j).gt.active_no3_limit1) then 
                           sminn_no3_diff          = n_from_active_no3(j) + n_from_nonmyc_no3(j) - active_no3_limit1
                           temp_n_flux = n_from_active_no3(j)
                           ! divide discrepancy between sources
                           n_from_active_no3(j)     = n_from_active_no3(j) - sminn_no3_diff &
                                                      * (n_from_active_no3(j) /(n_from_active_no3(j) + n_from_nonmyc_no3(j)))
                           n_from_nonmyc_no3(j)     = n_from_nonmyc_no3(j) - sminn_no3_diff &
                                                 * (n_from_nonmyc_no3(j) /(temp_n_flux + n_from_nonmyc_no3(j)))
                           npp_to_active_no3(j)     = n_from_active_no3(j) * cost_active_no3(p,j) 
                           npp_to_nonmyc_no3(j)     = n_from_nonmyc_no3(j) * cost_nonmyc_no3(p,j)
                                      
                       end if
                  
                       ! --------------------ACTIVE UPTAKE NH4 UPTAKE LIMIT------------------------!  
                       active_nh4_limit1          = sminn_nh4_layer_step(p,j,istp) *fixerfrac
                  
                      
                       ! trying to remove too much nh4 from soil. 
                       if (n_from_active_nh4(j) + n_from_nonmyc_nh4(j).gt.active_nh4_limit1) then 
                    
                          sminn_nh4_diff          = n_from_active_nh4(j) + n_from_nonmyc_nh4(j) - active_nh4_limit1
                          temp_n_flux = n_from_active_nh4(j)
                          ! divide discrepancy between sources
                          n_from_active_nh4(j)  = n_from_active_nh4(j)    - (sminn_nh4_diff &
                                                   * n_from_active_nh4(j) /(n_from_active_nh4(j) + n_from_nonmyc_nh4(j)))
                          n_from_nonmyc_nh4(j)  = n_from_nonmyc_nh4(j)    - (sminn_nh4_diff &
                                                   * n_from_nonmyc_nh4(j) /(temp_n_flux+ n_from_nonmyc_nh4(j)))
                          npp_to_active_nh4(j)  = n_from_active_nh4(j)    * cost_active_nh4(p,j) 
                          npp_to_nonmyc_nh4(j)  = n_from_nonmyc_nh4(j)    * cost_nonmyc_nh4(p,j)    
                                 
                       end if

                     
                                                               
                       ! How much N did we end up with
                       N_acquired                    =  n_from_active_no3(j)+n_from_nonmyc_no3(j) &
                                                       + n_from_active_nh4(j)+n_from_nonmyc_nh4(j)
                  
                  
                       ! How much did it actually cost? 
                       C_spent                       =   npp_to_active_no3(j)+npp_to_nonmyc_no3(j) &
                                                       + npp_to_active_nh4(j)+npp_to_nonmyc_nh4(j)

                      
                                                  
                       if(FIX==plants_are_fixing)then
                          N_acquired = N_acquired + n_from_fixation(j)
                          C_spent    = C_spent + npp_to_fixation(j) 
                       end if
                  
                  

                       ! How much C did we allocate or spend in this layer? 
                       npp_to_spend                 = npp_to_spend   - C_spent - (N_acquired &
                                                       * plantCN(p)*(1.0_r8+ grperc_n(p)))


                      
                  
                       ! Accumulate those fluxes
                       nt_uptake(p,istp)             = nt_uptake(p,istp)       + N_acquired
                       npp_uptake(p,istp)            = npp_uptake(p,istp)      + C_spent
                  
                                 
                  
                                                                                 
                       !-------------------- N flux accumulation------------!
                       n_active_no3_acc(p,istp)      = n_active_no3_acc(p,istp) + n_from_active_no3(j)
                       n_active_nh4_acc(p,istp)      = n_active_nh4_acc(p,istp) + n_from_active_nh4(j)
                       n_nonmyc_no3_acc(p,istp)      = n_nonmyc_no3_acc(p,istp) + n_from_nonmyc_no3(j)
                       n_nonmyc_nh4_acc(p,istp)      = n_nonmyc_nh4_acc(p,istp) + n_from_nonmyc_nh4(j)                 
            
                       !-------------------- C flux accumulation------------!
                       npp_active_no3_acc(p,istp) = npp_active_no3_acc(p,istp)  + npp_to_active_no3(j)
                       npp_active_nh4_acc(p,istp) = npp_active_nh4_acc(p,istp)  + npp_to_active_nh4(j)
                       npp_nonmyc_no3_acc(p,istp) = npp_nonmyc_no3_acc(p,istp)  + npp_to_nonmyc_no3(j)
                       npp_nonmyc_nh4_acc(p,istp) = npp_nonmyc_nh4_acc(p,istp)  + npp_to_nonmyc_nh4(j) 

                                    
                  
                       if(FIX == plants_are_fixing)then
                         n_fix_acc(p,istp)          = n_fix_acc(p,istp)         + n_from_fixation(j)
                         npp_fix_acc(p,istp)        = npp_fix_acc(p,istp)       + npp_to_fixation(j)
                       end if
                  
                 end do    ! j
             
             
                 ! check that we get the right amount of N...
             
            
             
                 ! Occasionally, the algorithm will want to extract a high fraction of NPP from a pool (eg leaves) that                               
                 ! quickly empties. One solution to this is to iterate round all the calculations starting from                                       
                 ! the cost functions. The other is to burn off the extra carbon and hope this doesn't happen very often...                     

                 if (npp_to_spend .ge. 1.e-13_r8)then
                       burned_off_carbon =  burned_off_carbon + npp_to_spend
                     !write(iulog,*) 'burned_off_carbon=', burned_off_carbon
                 end if

                 
             
                      
                 ! add vertical fluxes to patch arrays 
                 do j = 1,nlevdecomp
                       n_active_no3_vr(p,j)      =  n_active_no3_vr(p,j)      + n_from_active_no3(j)
                       n_active_nh4_vr(p,j)      =  n_active_nh4_vr(p,j)      + n_from_active_nh4(j)
                       n_nonmyc_no3_vr(p,j)      =  n_nonmyc_no3_vr(p,j)      + n_from_nonmyc_no3(j)
                       n_nonmyc_nh4_vr(p,j)      =  n_nonmyc_nh4_vr(p,j)      + n_from_nonmyc_nh4(j) 

                     
                 end do
               end if !unmet demand`

           if(use_funp)then
              !-------------------------------------------------------------------------------
               !           Spend C on extracting P.
               !-------------------------------------------------------------------------------
               if (plant_pdemand_pool_step(p,istp) .gt. 0._r8) then    ! unmet demand
  
                 !if(local_use_flexiblecn)then   !(Comment FlexCN bit)
                 !    if (leafn(p) == 0.0_r8) then   ! to avoid division by zero
                 !      delta_CN = fun_cn_flex_c(ivt(p))   ! Max CN ratio over standard
                 !    else
                 !      delta_CN = (leafc(p)+leafc_storage(p))/(leafn(p)+leafn_storage(p)) - leafcn(ivt(p)) ! leaf CN ratio                                                              
                 !    end if
                     ! C used for uptake is reduced if the cost of N is very high                
                 !    frac_ideal_C_use = max(0.0_r8,1.0_r8 - (total_N_resistance-fun_cn_flex_a(ivt(p)))/fun_cn_flex_b(ivt(p)) )
                     ! then, if the plant is very much in need of N, the C used for uptake is increased accordingly.                  
                 !    if(delta_CN .gt.0.and. frac_ideal_C_use.lt.1.0)then           
                 !      frac_ideal_C_use = frac_ideal_C_use + (1.0_r8-frac_ideal_C_use)*min(1.0_r8, delta_CN/fun_cn_flex_c(ivt(p)))
                 !    end if    
                     ! If we have too much N (e.g. from free N retranslocation) then make frac_ideal_c_use even lower.    
                     ! For a CN delta of fun_cn_flex_c, then we reduce C expendiure to the minimum of 0.5. 
                     ! This seems a little intense? 
                 !    if(delta_CN.lt.0.0)then
                 !       frac_ideal_C_use = frac_ideal_C_use + 0.5_r8*(1.0_r8*delta_CN/fun_cn_flex_c(ivt(p)))
                 !    endif 
                 !    frac_ideal_C_use = max(min(1.0_r8,frac_ideal_C_use),0.5_r8) 
                     ! don't let this go above 1 or below an arbirtray minimum (to prevent zero N uptake). 
                 !else
                     frac_ideal_C_use= 1.0_r8
                 !end if (Comment FlexCN bit)
                 
               
              
               
                   
                       !frac_ideal_C_use= 1.0_r8
                       !end if (Comment FlexCN bit)
               
                       excess_carbon_p = npp_to_spend_p * (1.0_r8-frac_ideal_c_use)
                       
                       if (excess_carbon_p*(1.0_r8+grperc_p(p)) .gt. npp_to_spend_p) then !prevent negative dnpp
                          excess_carbon_p =  npp_to_spend_p/(1.0_r8 + grperc_p(p))
                       end if
                   
                
                 !END Phosphorus

              
                 ! This is the main equation of FUN, which figures out how much C to spend on uptake to remain at the target CN ratio. 
                 ! nb. This term assumes that cost of N is constant through the timestep, because we don't have 
                 ! a concept of Michealis Menten kinetics. 
                 ! 
                 !Calculate the hypothetical amount of NPP that we should use to extract N over whole profile
                 !This calculation is based on the simulataneous solution of the uptake and extrction N balance. 
                 !It satisfies the criteria (spentC+growthC=availC AND spentC/cost=growthC/plantCN
                 !Had to add growth respiration here to balance carbon pool. 

         
               
                   excess_carbon_acc_p             = excess_carbon_acc_p + excess_carbon_p

                   ! spend less C than you have to to meet the target, thus allowing C:P ratios to rise. 
                   npp_to_spend_p         = npp_to_spend_p - excess_carbon_p*(1.0_r8+grperc_p(p))

                   dnpp_p  = npp_to_spend_p / ( (1.0_r8+grperc_p(p))*(plantCP(p) / total_P_resistance) + 1._r8)  

                   dnpp_p  = dnpp_p * frac_ideal_C_use
                   
           
                   !hypothetical amount of P acquired. 
                   dp    = dnpp_p / total_P_resistance
                

                 do j = 1,nlevdecomp
                        
                     ! RF How much of this NPP carbon do we allocate to the different pathways? fraction x gC/m2/s?
                     ! Could this code now be put in a matrix? 

                     

                    
                      npp_to_active_pox(j) = npp_frac_to_active_pox(j) * dnpp_p
                      npp_to_nonmyc_pox(j) = npp_frac_to_nonmyc_pox(j) * dnpp_p
                    
                     
                    
       
                   
                      p_from_active_pox(j) = npp_to_active_pox(j)  / cost_active_pox(p,j)
                      p_from_nonmyc_pox(j) = npp_to_nonmyc_pox(j)  / cost_nonmyc_pox(p,j)
                    
                
                                                            
                 end do
              
                 ! did we exceed the limits of uptake for any of these pools?
                 do j = 1,nlevdecomp    
                  
                     
                  
                     
                     
                      
! --------------------ACTIVE UPTAKE POX UPTAKE LIMIT------------------------!  
                       active_pox_limit2          = sminp_pox_layer_step(p,j,istp) *fixerfrac_p
                  
                      
                       ! trying to remove too much pox from soil. 
                       if (p_from_active_pox(j) + p_from_nonmyc_pox(j).gt.active_pox_limit2) then 
                    
                          sminp_pox_diff          = p_from_active_pox(j) + p_from_nonmyc_pox(j) - active_pox_limit2
                          temp_p_flux = p_from_active_pox(j)
                          ! divide discrepancy between sources
                          p_from_active_pox(j)  = p_from_active_pox(j)    - (sminp_pox_diff &
                                                   * p_from_active_pox(j) /(p_from_active_pox(j) + p_from_nonmyc_pox(j)))
                          p_from_nonmyc_pox(j)  = p_from_nonmyc_pox(j)    - (sminp_pox_diff &
                                                   * p_from_nonmyc_pox(j) /(temp_p_flux+ p_from_nonmyc_pox(j)))
                          npp_to_active_pox(j)  = p_from_active_pox(j)    * cost_active_pox(p,j) 
                          npp_to_nonmyc_pox(j)  = p_from_nonmyc_pox(j)    * cost_nonmyc_pox(p,j)    
                                 
                       end if
                      
                                                               
                      
                  
                     
                       ! How much P did we end up with
                       P_acquired                    =  p_from_active_pox(j)+p_from_nonmyc_pox(j) 
                  
                 
                       ! How much did it actually cost? 
                       C_spentP                       =   npp_to_active_pox(j)+ npp_to_nonmyc_pox(j) 

   
                       ! How much C did we allocate or spend in this layer? 
                      
                      
                          npp_to_spend_p                 = npp_to_spend_p   - C_spentP - (P_acquired &
                                                       * plantCP(p)*(1.0_r8+ grperc_p(p)))

                     
                         ! Accumulate those fluxes
                         pt_uptake(p,istp)             = pt_uptake(p,istp)       + P_acquired
                         npp_uptake_p(p,istp)            = npp_uptake_p(p,istp)      + C_spentP
                                  
                       
                       !-------------------- P flux accumulation------------!
                       p_active_pox_acc(p,istp)      = p_active_pox_acc(p,istp) + p_from_active_pox(j)
                       p_nonmyc_pox_acc(p,istp)      = p_nonmyc_pox_acc(p,istp) + p_from_nonmyc_pox(j)
                 
            
                       !-------------------- C flux accumulation------------!
                       npp_active_pox_acc(p,istp) = npp_active_pox_acc(p,istp)  + npp_to_active_pox(j)
                       npp_nonmyc_pox_acc(p,istp) = npp_nonmyc_pox_acc(p,istp)  + npp_to_nonmyc_pox(j)
 
                                    
                  
                  
                 end do    ! j
             
             
                 ! check that we get the right amount of N...
             
            
             
                 ! Occasionally, the algorithm will want to extract a high fraction of NPP from a pool (eg leaves) that                               
                 ! quickly empties. One solution to this is to iterate round all the calculations starting from                                       
                 ! the cost functions. The other is to burn off the extra carbon and hope this doesn't happen very often...                     

               

                       
                 ! ──────────────────────────────────────────────────────────────
                 ! FIX: Recycle unspent P-budget C back to supplementary N uptake
                 ! Instead of burning off leftover P-budget carbon, use it for
                 ! additional N acquisition. This prevents N starvation at P-rich
                 ! sites (e.g. Manaus) where the upfront C split gives ~50% to P
                 ! but P is so cheap that almost none is spent.
                 ! Based on Allen et al. FUN-P R model which solves N and P from
                 ! a single C pool (leftover P-C naturally goes to N+growth).
                 ! ──────────────────────────────────────────────────────────────
                   if (npp_to_spend_p .ge. 1.e-13_r8 .and. &
                       plant_ndemand_pool_step(p,istp) .gt. 0._r8) then

                     ! Use leftover P-budget C for supplementary N acquisition
                     npp_to_spend_supplementary = npp_to_spend_p

                     ! Same FUN equation as the main N section:
                     ! dnpp = C_avail / ((1+grperc)*plantCN/total_N_resistance + 1)
                     dnpp  = npp_to_spend_supplementary / &
                             ( (1.0_r8+grperc_n(p))*(plantCN(p) / total_N_resistance) + 1._r8)

                     ! Hypothetical N acquired
                     dn    = dnpp / total_N_resistance

                     ! Allocate to N pathways using same fractions from earlier
                     do j = 1,nlevdecomp
                       npp_to_active_nh4(j) = npp_frac_to_active_nh4(j) * dnpp
                       npp_to_nonmyc_nh4(j) = npp_frac_to_nonmyc_nh4(j) * dnpp
                       npp_to_active_no3(j) = npp_frac_to_active_no3(j) * dnpp
                       npp_to_nonmyc_no3(j) = npp_frac_to_nonmyc_no3(j) * dnpp
                       if(FIX==plants_are_fixing)then
                         npp_to_fixation(j) = npp_frac_to_fixation(j) * dnpp
                       else
                         npp_to_fixation(j) = 0.0_r8
                       end if

                       n_from_active_nh4(j) = npp_to_active_nh4(j) / cost_active_nh4(p,j)
                       n_from_nonmyc_nh4(j) = npp_to_nonmyc_nh4(j) / cost_nonmyc_nh4(p,j)
                       n_from_active_no3(j) = npp_to_active_no3(j) / cost_active_no3(p,j)
                       n_from_nonmyc_no3(j) = npp_to_nonmyc_no3(j) / cost_nonmyc_no3(p,j)
                       if(FIX==plants_are_fixing)then
                         n_from_fixation(j) = npp_to_fixation(j) / cost_fix(p,j)
                       else
                         n_from_fixation(j) = 0.0_r8
                       end if
                     end do

                     ! Check soil N limits (subtract what first N pass already took)
                     do j = 1,nlevdecomp
                       ! NO3 limit: total available minus what n_active_no3_vr already extracted
                       ! n_active_no3_vr already includes the first N pass extraction
                       active_no3_limit1 = max(0.0_r8, &
                         sminn_no3_layer_step(p,j,istp) * fixerfrac &
                         - n_active_no3_vr(p,j) - n_nonmyc_no3_vr(p,j))

                       if (n_from_active_no3(j) + n_from_nonmyc_no3(j) .gt. active_no3_limit1) then
                         sminn_no3_diff = n_from_active_no3(j) + n_from_nonmyc_no3(j) - active_no3_limit1
                         temp_n_flux = n_from_active_no3(j)
                         if (n_from_active_no3(j) + n_from_nonmyc_no3(j) .gt. 0.0_r8) then
                           n_from_active_no3(j) = n_from_active_no3(j) - sminn_no3_diff &
                             * (n_from_active_no3(j) / (n_from_active_no3(j) + n_from_nonmyc_no3(j)))
                           n_from_nonmyc_no3(j) = n_from_nonmyc_no3(j) - sminn_no3_diff &
                             * (n_from_nonmyc_no3(j) / (temp_n_flux + n_from_nonmyc_no3(j)))
                         else
                           n_from_active_no3(j) = 0.0_r8
                           n_from_nonmyc_no3(j) = 0.0_r8
                         end if
                         n_from_active_no3(j) = max(0.0_r8, n_from_active_no3(j))
                         n_from_nonmyc_no3(j) = max(0.0_r8, n_from_nonmyc_no3(j))
                         npp_to_active_no3(j) = n_from_active_no3(j) * cost_active_no3(p,j)
                         npp_to_nonmyc_no3(j) = n_from_nonmyc_no3(j) * cost_nonmyc_no3(p,j)
                       end if

                       ! NH4 limit
                       active_nh4_limit1 = max(0.0_r8, &
                         sminn_nh4_layer_step(p,j,istp) * fixerfrac &
                         - n_active_nh4_vr(p,j) - n_nonmyc_nh4_vr(p,j))

                       if (n_from_active_nh4(j) + n_from_nonmyc_nh4(j) .gt. active_nh4_limit1) then
                         sminn_nh4_diff = n_from_active_nh4(j) + n_from_nonmyc_nh4(j) - active_nh4_limit1
                         temp_n_flux = n_from_active_nh4(j)
                         if (n_from_active_nh4(j) + n_from_nonmyc_nh4(j) .gt. 0.0_r8) then
                           n_from_active_nh4(j) = n_from_active_nh4(j) - (sminn_nh4_diff &
                             * n_from_active_nh4(j) / (n_from_active_nh4(j) + n_from_nonmyc_nh4(j)))
                           n_from_nonmyc_nh4(j) = n_from_nonmyc_nh4(j) - (sminn_nh4_diff &
                             * n_from_nonmyc_nh4(j) / (temp_n_flux + n_from_nonmyc_nh4(j)))
                         else
                           n_from_active_nh4(j) = 0.0_r8
                           n_from_nonmyc_nh4(j) = 0.0_r8
                         end if
                         n_from_active_nh4(j) = max(0.0_r8, n_from_active_nh4(j))
                         n_from_nonmyc_nh4(j) = max(0.0_r8, n_from_nonmyc_nh4(j))
                         npp_to_active_nh4(j) = n_from_active_nh4(j) * cost_active_nh4(p,j)
                         npp_to_nonmyc_nh4(j) = n_from_nonmyc_nh4(j) * cost_nonmyc_nh4(p,j)
                       end if

                       ! Accumulate supplementary N and C
                       N_acquired = n_from_active_no3(j) + n_from_nonmyc_no3(j) &
                                  + n_from_active_nh4(j) + n_from_nonmyc_nh4(j)
                       C_spent = npp_to_active_no3(j) + npp_to_nonmyc_no3(j) &
                               + npp_to_active_nh4(j) + npp_to_nonmyc_nh4(j)

                       if(FIX==plants_are_fixing)then
                         N_acquired = N_acquired + n_from_fixation(j)
                         C_spent    = C_spent + npp_to_fixation(j)
                       end if

                       npp_to_spend_supplementary = npp_to_spend_supplementary &
                         - C_spent - (N_acquired * plantCN(p) * (1.0_r8 + grperc_n(p)))

                       ! Accumulate into N flux arrays (same as first N pass)
                       nt_uptake(p,istp)  = nt_uptake(p,istp)  + N_acquired
                       npp_uptake(p,istp) = npp_uptake(p,istp) + C_spent

                       n_active_no3_acc(p,istp) = n_active_no3_acc(p,istp) + n_from_active_no3(j)
                       n_active_nh4_acc(p,istp) = n_active_nh4_acc(p,istp) + n_from_active_nh4(j)
                       n_nonmyc_no3_acc(p,istp) = n_nonmyc_no3_acc(p,istp) + n_from_nonmyc_no3(j)
                       n_nonmyc_nh4_acc(p,istp) = n_nonmyc_nh4_acc(p,istp) + n_from_nonmyc_nh4(j)

                       npp_active_no3_acc(p,istp) = npp_active_no3_acc(p,istp) + npp_to_active_no3(j)
                       npp_active_nh4_acc(p,istp) = npp_active_nh4_acc(p,istp) + npp_to_active_nh4(j)
                       npp_nonmyc_no3_acc(p,istp) = npp_nonmyc_no3_acc(p,istp) + npp_to_nonmyc_no3(j)
                       npp_nonmyc_nh4_acc(p,istp) = npp_nonmyc_nh4_acc(p,istp) + npp_to_nonmyc_nh4(j)

                       if(FIX == plants_are_fixing)then
                         n_fix_acc(p,istp)   = n_fix_acc(p,istp)   + n_from_fixation(j)
                         npp_fix_acc(p,istp) = npp_fix_acc(p,istp) + npp_to_fixation(j)
                       end if

                       ! Update vertical N extraction tracking
                       n_active_no3_vr(p,j) = n_active_no3_vr(p,j) + n_from_active_no3(j)
                       n_active_nh4_vr(p,j) = n_active_nh4_vr(p,j) + n_from_active_nh4(j)
                       n_nonmyc_no3_vr(p,j) = n_nonmyc_no3_vr(p,j) + n_from_nonmyc_no3(j)
                       n_nonmyc_nh4_vr(p,j) = n_nonmyc_nh4_vr(p,j) + n_from_nonmyc_nh4(j)

                     end do  ! j (supplementary N pass)

                     ! Any true leftover after supplementary N pass → burn off (N-side)
                     if (npp_to_spend_supplementary .ge. 1.e-13_r8) then
                       burned_off_carbon = burned_off_carbon + npp_to_spend_supplementary
                     end if

                     ! P-side burned-off is now zero (all redirected to N)
                     ! npp_to_spend_p was fully consumed

                   else if (npp_to_spend_p .ge. 1.e-13_r8) then
                     ! No unmet N demand — burn off P-budget C as before
                     burned_off_carbon_p = burned_off_carbon_p + npp_to_spend_p
                   end if
             
                      
                 ! add vertical fluxes to patch arrays 
                 do j = 1,nlevdecomp
 
                         p_active_pox_vr(p,j)      =  p_active_pox_vr(p,j)      + p_from_active_pox(j)
                         p_nonmyc_pox_vr(p,j)      =  p_nonmyc_pox_vr(p,j)      + p_from_nonmyc_pox(j) 
                      
                 end do
               end if !unmet demand`
             end if !FUNP
            
            end do fix_loop ! FIXER. 
             
            if (istp.eq.ecm_step) then
               n_ecm_no3_acc(p)          =  n_active_no3_acc(p,istp)
               n_ecm_nh4_acc(p)          =  n_active_nh4_acc(p,istp)
               if(use_funp)then
                 p_ecm_pox_acc(p)        =  p_active_pox_acc(p,istp)
               end if
            else
               n_am_no3_acc(p)           =  n_active_no3_acc(p,istp)
               n_am_nh4_acc(p)           =  n_active_nh4_acc(p,istp)
               if(use_funp)then
                 p_am_pox_acc(p)         =  p_active_pox_acc(p,istp)
               end if
            end if
            
            ! Accumulate total column N fluxes over istp
            n_active_no3_acc_total(p)    =  n_active_no3_acc_total(p)    + n_active_no3_acc(p,istp)
            n_active_nh4_acc_total(p)    =  n_active_nh4_acc_total(p)    + n_active_nh4_acc(p,istp)
            n_nonmyc_no3_acc_total(p)    =  n_nonmyc_no3_acc_total(p)    + n_nonmyc_no3_acc(p,istp)
            n_nonmyc_nh4_acc_total(p)    =  n_nonmyc_nh4_acc_total(p)    + n_nonmyc_nh4_acc(p,istp)
            n_fix_acc_total(p)           =  n_fix_acc_total(p)           + n_fix_acc(p,istp)
            n_retrans_acc_total(p)       =  n_retrans_acc_total(p)       + n_retrans_acc(p,istp)
            free_nretrans(p)             =  free_nretrans(p)            + free_nretrans_acc(p,istp)
      
            ! Accumulate total column C fluxes over istp
            npp_active_no3_acc_total(p)  =  npp_active_no3_acc_total(p)  + npp_active_no3_acc(p,istp)
            npp_active_nh4_acc_total(p)  =  npp_active_nh4_acc_total(p)  + npp_active_nh4_acc(p,istp)
            npp_nonmyc_no3_acc_total(p)  =  npp_nonmyc_no3_acc_total(p)  + npp_nonmyc_no3_acc(p,istp)
            npp_nonmyc_nh4_acc_total(p)  =  npp_nonmyc_nh4_acc_total(p)  + npp_nonmyc_nh4_acc(p,istp)
            npp_fix_acc_total(p)         =  npp_fix_acc_total(p)         + npp_fix_acc(p,istp)
            npp_retrans_acc_total(p)     =  npp_retrans_acc_total(p)     + npp_retrans_acc(p,istp) 

            if(use_funp)then
              ! Accumulate total column P fluxes over istp
              p_active_pox_acc_total(p)    =  p_active_pox_acc_total(p)    + p_active_pox_acc(p,istp)
              p_nonmyc_pox_acc_total(p)    =  p_nonmyc_pox_acc_total(p)    + p_nonmyc_pox_acc(p,istp)
              p_retrans_acc_total(p)       =  p_retrans_acc_total(p)       + p_retrans_acc(p,istp)
              free_pretrans(p)             =  free_pretrans(p)            + free_pretrans_acc(p,istp)
      
              ! Accumulate total column C fluxes over istp
              npp_active_pox_acc_total(p)  =  npp_active_pox_acc_total(p)  + npp_active_pox_acc(p,istp)
              npp_nonmyc_pox_acc_total(p)  =  npp_nonmyc_pox_acc_total(p)  + npp_nonmyc_pox_acc(p,istp)
              npp_retrans_p_acc_total(p)   =  npp_retrans_p_acc_total(p)     + npp_retrans_p_acc(p,istp) 
            end if
                   
         !end if  ! plant_ndemand_pool_step > 0._r8
      end do stp ! NSTEP 

   
      !-------------------------------------------------------------------------------
      ! Turn step level quantities back into fluxes per second. 
      !-------------------------------------------------------------------------------

      !---------------------------N fluxes--------------------!
      Npassive(p)               = n_passive_acc(p)/dt
      Nfix(p)                   = n_fix_acc_total(p)/dt                   
      retransn_to_npool(p)      = n_retrans_acc_total(p)/dt
      free_retransn_to_npool(p) = free_nretrans(p)/dt
      ! this is the N that comes off leaves. 
      Nretrans(p)               = retransn_to_npool(p) + free_retransn_to_npool(p)

      if(use_funp)then
        !---------------------------P fluxes--------------------!
        Ppassive(p)               = p_passive_acc(p)/dt                  
        retransp_to_ppool(p)      = p_retrans_acc_total(p)/dt
        free_retransp_to_ppool(p) = free_pretrans(p)/dt
        ! this is the P that comes off leaves. 
        Pretrans(p)               = retransp_to_ppool(p) + free_retransp_to_ppool(p)
      end if
      
      
      
      
      !Extract active uptake N from soil pools. 
      do j = 1, nlevdecomp
         !RF change. The N fixed doesn't actually come out of the soil mineral pools, it is 'new'... 
         sminn_to_plant_fun_no3_vr(p,j)    = (n_passive_no3_vr(p,j)  + n_active_no3_vr(p,j) &
                                             + n_nonmyc_no3_vr(p,j))/(dzsoi_decomp(j)*dt)
         sminn_to_plant_fun_nh4_vr(p,j)    = (n_passive_nh4_vr(p,j)  + n_active_nh4_vr(p,j) &
                                             + n_nonmyc_nh4_vr(p,j))/(dzsoi_decomp(j)*dt)

      if(use_funp)then
        sminp_to_plant_fun_vr(p,j)    = (p_passive_pox_vr(p,j)  + p_active_pox_vr(p,j) &
                                             + p_nonmyc_pox_vr(p,j))/(dzsoi_decomp(j)*dt)
         
      end if
         
      end do
      
     
      
      Nactive_no3(p)            = n_active_no3_acc_total(p)/dt   + n_active_no3_retrans_total(p)/dt
      Nactive_nh4(p)            = n_active_nh4_acc_total(p)/dt   + n_active_nh4_retrans_total(p)/dt  
      
      
    
      Necm_no3(p)               = n_ecm_no3_acc(p)/dt            + n_ecm_no3_retrans(p)/dt
      Necm_nh4(p)               = n_ecm_nh4_acc(p)/dt            + n_ecm_nh4_retrans(p)/dt      
      Necm(p)                   = Necm_no3(p) + Necm_nh4(p)
      Nam_no3(p)                = n_am_no3_acc(p)/dt             + n_am_no3_retrans(p)/dt
      Nam_nh4(p)                = n_am_nh4_acc(p)/dt             + n_am_nh4_retrans(p)/dt
      Nam(p)                    = Nam_no3(p) + Nam_nh4(p)
      Nnonmyc_no3(p)            = n_nonmyc_no3_acc_total(p)/dt   + n_nonmyc_no3_retrans_total(p)/dt
      Nnonmyc_nh4(p)            = n_nonmyc_nh4_acc_total(p)/dt   + n_nonmyc_nh4_retrans_total(p)/dt
      Nnonmyc(p)                = Nnonmyc_no3(p) + Nnonmyc_nh4(p)
      plant_ndemand_retrans(p)  = plant_ndemand_retrans(p)/dt
      Nuptake(p)                = Nactive_no3(p) + Nactive_nh4(p) + Nnonmyc_no3(p) &
                                  + Nnonmyc_nh4(p) + Nfix(p) + Npassive(p) + &
                                  retransn_to_npool(p)+free_retransn_to_npool(p) 
      Nactive(p)                = Nactive_no3(p)  + Nactive_nh4(p) !+ Nnonmyc_no3(p) + Nnonmyc_nh4(p)
                                   
     ! free N goes straight to the npool, not throught Nuptake...
      sminn_to_plant_fun(p)     = Nactive_no3(p) + Nactive_nh4(p) + Nnonmyc_no3(p) + Nnonmyc_nh4(p) + Nfix(p) + Npassive(p)
 
 
      soil_n_extraction = ( sum(n_active_no3_vr(p,1: nlevdecomp))+sum(n_nonmyc_no3_vr(p,1: nlevdecomp))+&
      sum(n_active_nh4_vr(p,1: nlevdecomp)) + sum(n_nonmyc_nh4_vr(p,1: nlevdecomp)))

     if(use_funp)then
      Pactive(p)            = p_active_pox_acc_total(p)/dt   + p_active_pox_retrans_total(p)/dt
  
           
    
      Pecm(p)               = p_ecm_pox_acc(p)/dt            + p_ecm_pox_retrans(p)/dt
      
      Pam(p)                = p_am_pox_acc(p)/dt             + p_am_pox_retrans(p)/dt

      Pnonmyc(p)            = p_nonmyc_pox_acc_total(p)/dt   + p_nonmyc_pox_retrans_total(p)/dt
  
      plant_pdemand_retrans(p)  = plant_pdemand_retrans(p)/dt
      Puptake(p)                = Pactive(p) + Pnonmyc(p) &
                                  + Ppassive(p)  &
                                  + retransp_to_ppool(p) &
                                  + free_retransp_to_ppool(p) 
      Pactive(p)                = Pactive(p) !+ Pnonmyc(p) 
                                   
     ! free P goes straight to the ppool, not throught Puptake...
      sminp_to_plant_fun(p)     = Pactive(p) + Pnonmyc(p) + Ppassive(p)
 
 
      soil_p_extraction =  sum(p_active_pox_vr(p,1: nlevdecomp))  +sum(p_nonmyc_pox_vr(p,1: nlevdecomp))
     

     end if
      
      !---------------------------C fluxes--------------------!

      npp_Nactive_no3(p)        = npp_active_no3_acc_total(p)/dt + npp_active_no3_retrans_total(p)/dt
      npp_Nactive_nh4(p)        = npp_active_nh4_acc_total(p)/dt + npp_active_nh4_retrans_total(p)/dt
   


      npp_Nnonmyc_no3(p)        = npp_nonmyc_no3_acc_total(p)/dt + npp_nonmyc_no3_retrans_total(p)/dt
      npp_Nnonmyc_nh4(p)        = npp_nonmyc_nh4_acc_total(p)/dt + npp_nonmyc_nh4_retrans_total(p)/dt
      npp_Nactive(p)            = npp_Nactive_no3(p) + npp_Nactive_nh4(p) !+ npp_Nnonmyc_no3(p) + npp_Nnonmyc_nh4(p)
      npp_Nnonmyc(p)            = npp_Nnonmyc_no3(p) + npp_Nnonmyc_nh4(p)              
      npp_Nfix(p)               = npp_fix_acc_total(p)/dt      
      npp_Nretrans(p)           = npp_retrans_acc_total(p)/dt  

      if(use_funp)then
        !---------------------------C fluxes--------------------!

        npp_Pactive(p)        = npp_active_pox_acc_total(p)/dt + npp_active_pox_retrans_total(p)/dt
      
        npp_Pnonmyc(p)        = npp_nonmyc_pox_acc_total(p)/dt + npp_nonmyc_pox_retrans_total(p)/dt
      
        npp_Pactive(p)            = npp_Pactive(p) !+ npp_Pnonmyc(p)

        npp_Pnonmyc(p)            = npp_Pnonmyc(p)
         
        npp_Pretrans(p)           = npp_retrans_p_acc_total(p)/dt
  
      end if
     

      if (use_funp)then
      !---------------------------Extra Respiration--------------------! 
      !---------------------------Fluxes--------------------!      
      !---------------------------Nitrogen--------------------!

     soilc_change(p)           = (npp_active_no3_acc_total(p)      + npp_active_nh4_acc_total(p) &
                                    + npp_nonmyc_no3_acc_total(p)     &  
                                    + npp_nonmyc_nh4_acc_total(p)     + npp_fix_acc_total(p))/dt      &
                                    + npp_Nretrans(p) 

      soilc_change(p)           = soilc_change(p) + burned_off_carbon / dt

      burnedoff_carbon(p)       = burned_off_carbon/dt    
    
      npp_Nuptake(p)            = soilc_change(p)
 
      
      ! how much carbon goes to growth of tissues?  
      npp_growth(p)             = (Nuptake(p)- free_retransn_to_npool(p))*plantCN(p)+(excess_carbon_acc/dt) 
 !does not include gresp, since this is calculated from growth
      !---------------------------Phosphorus--------------------!
      soilc_change_p(p)           = (npp_active_pox_acc_total(p)   + &
                                    npp_nonmyc_pox_acc_total(p)     &  
                                    )/dt      &
                                    + npp_Pretrans(p)

      soilc_change_p(p)           = soilc_change_p(p) + (burned_off_carbon_p / dt)   

      soilc_change_p(p)           = soilc_change_p(p)/scale_availc  

     !?????? Should we add the costs of nitrogen ?
      !soilc_change(p)           = soilc_change(p) + soilc_change_p(p)      
  
      burnedoff_carbon_p(p)       = (burned_off_carbon_p/dt)/scale_availc   
         
      npp_Puptake(p)              = soilc_change_p(p)

      ! how much carbon goes to growth of tissues?
      npp_growth_p(p)             = (Puptake(p)- free_retransp_to_ppool(p))*plantCP(p)+((excess_carbon_acc_p/dt))/scale_availc   
      !?????? Should we add the costs of nitrogen ?
      !npp_growth(p) = npp_growth(p) + npp_growth_p(p)
      else 
      !---------------------------Extra Respiration Fluxes--------------------!      
      soilc_change(p)           = (npp_active_no3_acc_total(p)      + npp_active_nh4_acc_total(p) &
                                    + npp_nonmyc_no3_acc_total(p)     &  
                                    + npp_nonmyc_nh4_acc_total(p)     + npp_fix_acc_total(p))/dt      &
                                    + npp_Nretrans(p)
      soilc_change(p)           = soilc_change(p) + burned_off_carbon / dt                 
      burnedoff_carbon(p)       = burned_off_carbon/dt          
      npp_Nuptake(p)            = soilc_change(p)
      ! how much carbon goes to growth of tissues?  
      npp_growth(p)             = (Nuptake(p)- free_retransn_to_npool(p))*plantCN(p)+(excess_carbon_acc/dt) !does not include gresp, since this is calculated from growth
      end if

     
      !-----------------------Diagnostic Fluxes------------------------------!
      if(availc(p).gt.0.0_r8)then !what happens in the night? 
        nuptake_npp_fraction_patch(p) = npp_Nuptake(p)/availc(p)
      else
        nuptake_npp_fraction_patch(p) = 0.0_r8
      endif 
      if(npp_Nfix(p).gt.0.0_r8)then
        cost_nfix(p) = Nfix(p)/npp_Nfix(p)
      else
        cost_nfix(p) = 0.0_r8
      endif 
      if(npp_Nactive(p).gt.0.0_r8)then
        cost_nactive(p) = Nactive(p)/npp_Nactive(p)
      else
        cost_nactive(p) = 0.0_r8
      endif 
      if(npp_Nretrans(p).gt.0.0_r8)then
        cost_nretrans(p) = Nretrans(p)/npp_Nretrans(p)
      else
        cost_nretrans(p) = 0.0_r8
      endif 
     if(npp_Nnonmyc(p).gt.0.0_r8)then
        cost_nnonmyc(p) = Nnonmyc(p)/npp_Nnonmyc(p)
      else
        cost_nnonmyc(p) = 0.0_r8
      endif 

 



     if(use_funp)then
      !-----------------------Diagnostic Fluxes------------------------------!
      if(availc(p).gt.0.0_r8)then !what happens in the night? 
        puptake_npp_fraction_patch(p) = npp_Puptake(p)/(scale_availc*availc(p))
      else
        puptake_npp_fraction_patch(p) = 0.0_r8
      endif 
      if(npp_Pactive(p).gt.0.0_r8)then
        cost_pactive(p) = Pactive(p)/npp_Pactive(p)
      else
        cost_pactive(p) = 0.0_r8
      endif 
      if(npp_Pretrans(p).gt.0.0_r8)then
        cost_pretrans(p) = Pretrans(p)/npp_Pretrans(p)
      else
        cost_pretrans(p) = 0.0_r8
      endif 
      if(npp_Pnonmyc(p).gt.0.0_r8)then
        cost_pnonmyc(p) = Pnonmyc(p)/npp_Pnonmyc(p)
      else
        cost_pnonmyc(p) = 0.0_r8
      endif 


     end if
       
       
  end do pft ! PFT Ends 

  call t_stopf('CNFUNcalcs')

  call p2c(bounds, num_soilc, filter_soilc,               &
           veg_cf%soilc_change(bounds%begp:bounds%endp),  &
           col_cf%soilc_change(bounds%begc:bounds%endc))
           
  call p2c(bounds, num_soilc, filter_soilc,               &
           veg_nf%Nfix(bounds%begp:bounds%endp),          &
           col_nf%nfix_to_sminn(bounds%begc:bounds%endc))

  if(use_funp)then
  call p2c(bounds, num_soilc, filter_soilc,               &
           veg_cf%soilc_change_p(bounds%begp:bounds%endp),  &
           col_cf%soilc_change_p(bounds%begc:bounds%endc))

  end if
    end associate

  end subroutine CNFUN

!=========================================================================================
  real(r8) function fun_cost_fix(fixer,a_fix,b_fix,c_fix,big_cost,crootfr,s_fix, tc_soisno)

! Description:
!   Calculate the cost of fixing N by nodules.
! Code Description:
!   This code is written to CLM4CN by Mingjie Shi on 06/27/2013

  implicit none
!--------------------------------------------------------------------------
! Function result.
!--------------------------------------------------------------------------
! real(r8) , intent(out) :: cost_of_n   !!! cost of fixing N (kgC/kgN)
!--------------------------------------------------------------------------
! Scalar arguments with intent(in).
!--------------------------------------------------------------------------
  integer,  intent(in) :: fixer     ! flag indicating if plant is a fixer
                                    ! 1=yes, otherwise no.
  real(r8), intent(in) :: a_fix     ! As in Houlton et al. (Nature) 2008
  real(r8), intent(in) :: b_fix     ! As in Houlton et al. (Nature) 2008
  real(r8), intent(in) :: c_fix     ! As in Houlton et al. (Nature) 2008
  real(r8), intent(in) :: big_cost  ! an arbitrary large cost (gC/gN)
  real(r8), intent(in) :: crootfr   ! fraction of roots for carbon that are in this layer
  real(r8), intent(in) :: s_fix     ! Inverts Houlton et al. 2008 and constrains between 7.5 and 12.5
  real(r8), intent(in) :: tc_soisno ! soil temperature (degrees Celsius)

  if (fixer == 1 .and. crootfr > 1.e-6_r8) then
     fun_cost_fix  = s_fix * (exp(a_fix + b_fix * tc_soisno * (1._r8 - 0.5_r8 * tc_soisno / c_fix)) - 2._r8)
     
     
     ! New term to directly account for Ben Houlton's temperature response function. 
     ! Assumes s_fix is -6.  (RF, Jan 2015)  
     ! 1.25 converts from the Houlton temp response function to a 0-1 limitation factor. 
     ! The cost of N should probably be 6 gC/gN (or 9, including maintenance costs of nodules) 
     ! for 'optimal' temperatures. This cost should increase in a way that mirrors 
     ! Houlton et al's observations of temperautre limitations on the mirboial fixation rates. 
     ! We don't actually simulate the rate of fixation (and assume that N uptake is instantaneous) 
     ! here, so instead the limitation term is here rolled into the cost function.  
     
     ! Here we invert the 'cost' to give the optimal N:C ratio (1/6 gN/gC)  The amount of N 
     ! you get for a given C goes down as it gets colder, so this can be multiplied by 
     ! the temperature function to give a temperature-limited N:C of  f/6. This number 
     ! can then be inverted to give a temperature limited C:N, as 1/(f/6). Which is the 
     ! same as 6/f, given here" 
     fun_cost_fix  = (-1*s_fix) * 1.0_r8 / (1.25_r8* (exp(a_fix + b_fix * tc_soisno * (1._r8 - 0.5_r8 * tc_soisno / c_fix)) ))

     !fun_cost_fix  = (-1*(-1.0_r8)) * 1.0_r8 / (1.25_r8* (exp((-3.62_r8) + (0.27_r8) * tc_soisno * (1._r8 - 0.5_r8 * tc_soisno / (25.15_r8))) ))
  else
     fun_cost_fix = big_cost
  end if    ! ends up with the fixer or non-fixer decision
  
  end function fun_cost_fix

!=========================================================================================
  real(r8) function fun_cost_fix_Bytnerowicz_noAcc(fixer,Tmin_fix,Topt_fix,Tmax_fix,big_cost,crootfr,s_fix, tc_soisno)

! Description:
!   Calculate the cost of fixing N by nodules.
! Code Description:
!   This code is written to E3SM by Renato Braghiere 03/16/2023

  implicit none
!--------------------------------------------------------------------------
! Function result.
!--------------------------------------------------------------------------
! real(r8) , intent(out) :: cost_of_n   !!! cost of fixing N (kgC/kgN)
!--------------------------------------------------------------------------
  integer,  intent(in) :: fixer     ! flag indicating if plant is a fixer
                                    ! 1=yes, otherwise no.
  real(r8), intent(in) :: Tmin_fix  ! As in Bytnerowicz et al. (2022)    
  real(r8), intent(in) :: Topt_fix  ! As in Bytnerowicz et al. (2022)     
  real(r8), intent(in) :: Tmax_fix  ! As in Bytnerowicz et al. (2022)    
  real(r8), intent(in) :: big_cost  ! an arbitrary large cost (gC/gN)
  real(r8), intent(in) :: crootfr   ! fraction of roots for carbon that are in this layer
  real(r8), intent(in) :: s_fix     ! Inverts Houlton et al. 2008 and constrains between 7.5 and 12.5
  real(r8), intent(in) :: tc_soisno ! soil temperature (degrees Celsius)

  if (fixer == 1 .and. crootfr > 1.e-6_r8 .and. tc_soisno > Tmin_fix .and. tc_soisno < Tmax_fix) then
     fun_cost_fix_Bytnerowicz_noAcc  = (-1*s_fix) / ( ((Tmax_fix-tc_soisno)/(Tmax_fix-Topt_fix))*&
                                                    ( ((tc_soisno-Tmin_fix)/(Topt_fix-Tmin_fix))**&
                                                      ((Topt_fix- Tmin_fix)/(Tmax_fix-Topt_fix)) ) )
 
  !fun_cost_fix  = (-1*s_fix) * 1.0_r8 / (1.25_r8* (exp(a_fix + b_fix * tc_soisno * (1._r8 - 0.5_r8 * tc_soisno / c_fix)) ))
  else
     fun_cost_fix_Bytnerowicz_noAcc = big_cost
  end if    ! ends up with the fixer or non-fixer decision

  end function fun_cost_fix_Bytnerowicz_noAcc
!=========================================================================================


!=========================================================================================
  real(r8) function fun_cost_fix_Bytnerowicz_Acc(fixer,Tmin_fix,Topt_fix,Tmax_fix,big_cost,crootfr,s_fix, tc_soila10) 

! Description:
!   Calculate the cost of fixing N by nodules.
! Code Description:
!   This code is written to E3SM by Renato Braghiere 03/16/2023

  implicit none
!--------------------------------------------------------------------------
! Function result.
!--------------------------------------------------------------------------
! real(r8) , intent(out) :: cost_of_n   !!! cost of fixing N (kgC/kgN)
!--------------------------------------------------------------------------
  integer,  intent(in) :: fixer     ! flag indicating if plant is a fixer
                                    ! 1=yes, otherwise no.
  real(r8), intent(inout) :: Tmin_fix  ! As in Bytnerowicz et al. (2022)    
  real(r8), intent(inout) :: Topt_fix  ! As in Bytnerowicz et al. (2022)     
  real(r8), intent(inout) :: Tmax_fix  ! As in Bytnerowicz et al. (2022)    
  real(r8), intent(in) :: big_cost  ! an arbitrary large cost (gC/gN)
  real(r8), intent(in) :: crootfr   ! fraction of roots for carbon that are in this layer
  real(r8), intent(in) :: s_fix     ! Inverts Houlton et al. 2008 and constrains between 7.5 and 12.5
  real(r8), intent(in) :: tc_soila10 ! 10 day running mean soil temperature, 12 cm (degrees Celsius)

  ! Temperate temperature function
  if (tc_soila10 < 18.5_r8) then
     Tmin_fix = -2.04_r8
     Topt_fix = 32.10_r8  
     Tmax_fix = 43.98_r8 
  else if (tc_soila10 >= 18.5_r8 .and. tc_soila10 < 28.5_r8) then
     Tmin_fix = 0.697_r8 * tc_soila10 - 14.93_r8          
     Topt_fix = 0.047_r8 * tc_soila10 + 31.24_r8
     Tmax_fix = 0.009_r8 * tc_soila10 + 43.82_r8
  else
     Tmin_fix = 4.93_r8
     Topt_fix = 32.58_r8
     Tmax_fix = 44.08_r8
  end if
  ! Tropical temperature function !Tmax never changes!
  !if (tc_soila10 < 18.5_r8) then
  !   Tmin_fix = 2.37_r8  !parameter not the same as in noACC
  !   Topt_fix = 30.34_r8
  !else if (tc_soila10 >= 18.5_r8 .and. tc_soila10 < 28.5_r8) then
  !   Tmin_fix = 0.932_r8 * tc_soila10 - 14.87_r8
  !   Topt_fix = 0.574_r8 * tc_soila10 + 19.72_r8
  !else if (tc_soila10 >= 28.5_r8) then
  !   Tmin_fix = 11.69_r8
  !   Topt_fix = 36.08_r8  

  if (fixer == 1 .and. crootfr > 1.e-6_r8 .and. tc_soila10 > Tmin_fix .and. tc_soila10 < Tmax_fix) then
     fun_cost_fix_Bytnerowicz_Acc  = (-1*s_fix) / ( ((Tmax_fix-tc_soila10)/(Tmax_fix-Topt_fix))*&
                                                    ( ((tc_soila10-Tmin_fix)/(Topt_fix-Tmin_fix))**&
                                                      ((Topt_fix- Tmin_fix)/(Tmax_fix-Topt_fix)) ) )

  !fun_cost_fix  = (-1*s_fix) * 1.0_r8 / (1.25_r8* (exp(a_fix + b_fix * tc_soila10 * (1._r8 - 0.5_r8 * tc_soila10 / c_fix)) ))
  else
     fun_cost_fix_Bytnerowicz_Acc = big_cost
  end if    ! ends up with the fixer or non-fixer decision

  end function fun_cost_fix_Bytnerowicz_Acc
!=========================================================================================

!=========================================================================================
  real(r8) function fun_cost_active(sminn_layer,big_cost,kc_active,kn_active,rootc_dens,crootfr,smallValue)         

! Description:
!    Calculate the cost of active uptake of N frm the soil.
! Code Description:
!   This code is written to CLM4 by Mingjie Shi.

  implicit none
!--------------------------------------------------------------------------
! Function result.
!--------------------------------------------------------------------------
  real(r8), intent(in) :: sminn_layer   !  Amount of N (as NH4 or NO3) in the soil that is available to plants (gN/m2).
  real(r8), intent(in) :: big_cost      !  An arbitrary large cost (gC/gN).
  real(r8), intent(in) :: kc_active     !  Constant for cost of active uptake (gC/m2).
  real(r8), intent(in) :: kn_active     !  Constant for cost of active uptake (gC/m2).
  real(r8), intent(in) :: rootc_dens    !  Root carbon density in layer (gC/m3).
  real(r8), intent(in) :: crootfr        !  Fraction of roots that are in this layer.
  real(r8), intent(in) :: smallValue    !  A small number.

  if (rootc_dens > 1.e-6_r8.and.sminn_layer > smallValue) then
     fun_cost_active =  kn_active/sminn_layer + kc_active/rootc_dens 
  else
!    There are very few roots in this layer. Set a high cost.
     fun_cost_active =  big_cost
  end if
 
  end function fun_cost_active
!=========================================================================================
  real(r8) function fun_cost_nonmyc(sminn_layer,big_cost,kc_nonmyc,kn_nonmyc,rootc_dens,crootfr,smallValue)         

! Description:
!    Calculate the cost of nonmyc uptake of N frm the soil.
! Code Description:
!   This code is written to CLM4 by Mingjie Shi.

  implicit none
!--------------------------------------------------------------------------
! Function result.
!--------------------------------------------------------------------------
  real(r8), intent(in) :: sminn_layer   !  Amount of N (as NH4 or NO3) in the soil that is available to plants (gN/m2).
  real(r8), intent(in) :: big_cost      !  An arbitrary large cost (gC/gN).
  real(r8), intent(in) :: kc_nonmyc     !  Constant for cost of nonmyc uptake (gC/m2).
  real(r8), intent(in) :: kn_nonmyc     !  Constant for cost of nonmyc uptake (gC/m2).
  real(r8), intent(in) :: rootc_dens   !  Root carbon density in layer (gC/m3).
  real(r8), intent(in) :: crootfr        !  Fraction of roots that are in this layer.
  real(r8), intent(in) :: smallValue    !  A small number.

  if (rootc_dens > 1.e-6_r8.and.sminn_layer > smallValue) then
    fun_cost_nonmyc =  kn_nonmyc / sminn_layer + kc_nonmyc / rootc_dens 
  else
!   There are very few roots in this layer. Set a high cost.
    fun_cost_nonmyc = big_cost
  end if

  end function fun_cost_nonmyc

!==========================================================================

 subroutine fun_retranslocation(p,dt,npp_to_spend,total_falling_leaf_c,         &
               total_falling_leaf_n, total_n_resistance, total_c_spent_retrans, &
               total_c_accounted_retrans, free_n_retrans, paid_for_n_retrans,   &
               target_leafcn, grperc, plantCN)
!
! Description:
! This subroutine (should it be a function?) calculates the amount of N absorbed and C spent 
! during retranslocation. 
! Rosie Fisher. April 2016. 
! !USES:
  implicit none 

! !ARGUMENTS:
  real(r8), intent(IN) :: total_falling_leaf_c  ! INPUT  gC/m2/timestep
  real(r8), intent(IN) :: total_falling_leaf_n  ! INPUT  gC/m2/timestep
  real(r8), intent(IN) :: total_n_resistance    ! INPUT  gC/gN
  real(r8), intent(IN) :: npp_to_spend          ! INPUT  gN/m2/timestep
  real(r8), intent(IN) :: target_leafcn         ! INPUT  gC/gN
  real(r8), intent(IN) :: dt                    ! INPUT  seconds
  real(r8), intent(IN) :: grperc                ! INPUT growth respiration fraction
  real(r8), intent(IN) :: plantCN               ! INPUT plant CN ratio
  integer, intent(IN)  :: p                     ! INPUT  patch index

  real(r8), intent(OUT) :: total_c_spent_retrans     ! OUTPUT gC/m2/timestep
  real(r8), intent(OUT) :: total_c_accounted_retrans ! OUTPUT gC/m2/timestep
  real(r8), intent(OUT) :: paid_for_n_retrans        ! OUTPUT gN/m2/timestep
  real(r8), intent(OUT) :: free_n_retrans            ! OUTPUT gN/m2/timestep

  !
  ! !LOCAL VARIABLES:
  real(r8) :: kresorb               ! INTERNAL used factor
  real(r8) :: falling_leaf_c        ! INTERNAL gC/m2/timestep
  real(r8) :: falling_leaf_n        ! INTERNAL gN/m2/timestep
  real(r8) :: falling_leaf_cn       ! INTERNAL gC/gN
  real(r8) :: cost_retrans_temp     ! INTERNAL gC/gN
  real(r8) :: leaf_n_ext            ! INTERNAL gN/m2/timestep
  real(r8) :: c_spent_retrans       ! INTERNAL gC/m2/timestep
  real(r8) :: c_accounted_retrans   ! INTERNAL gC/m2/timestep
  real(r8) :: npp_to_spend_temp     ! INTERNAL gC/m2/timestep
  real(r8) :: max_falling_leaf_cn   ! INTERNAL gC/gN
  real(r8) :: min_falling_leaf_cn   ! INTERNAL gC/gN
  real(r8) :: cost_escalation       ! INTERNAL cost function parameter
  integer  :: iter                  ! INTERNAL
  integer  :: exitloop              ! INTERNAL
  ! ------------------------------------------------------------------------------- 


   ! ------------------ Initialize total fluxes. ------------------!
   total_c_spent_retrans = 0.0_r8
   total_c_accounted_retrans = 0.0_r8
   c_accounted_retrans   = 0.0_r8
   paid_for_n_retrans    = 0.0_r8
   npp_to_spend_temp     = npp_to_spend

   ! ------------------ Initial C and N pools in falling leaves. ------------------!
   falling_leaf_c       =  total_falling_leaf_c      
   falling_leaf_n       =  total_falling_leaf_n 

   !  ------------------ PARAMETERS ------------------ 
   max_falling_leaf_cn = target_leafcn * 3.0_r8 
   min_falling_leaf_cn = target_leafcn * 1.5_r8
   cost_escalation     = 1.3_r8

   !  ------------------ Free uptake ------------------ 
   free_n_retrans  = max(falling_leaf_n -  (falling_leaf_c/min_falling_leaf_cn),0.0_r8)
   
   falling_leaf_n = falling_leaf_n -  free_n_retrans 

   ! ------------------ Initial CN ratio and costs ------------------!  
   falling_leaf_cn      = falling_leaf_c/falling_leaf_n 
   kresorb =  (1.0_r8/target_leafcn)
   cost_retrans_temp    = kresorb / ((1.0_r8/falling_leaf_cn )**1.3_r8)

   ! ------------------ Iteration loops to figure out extraction limit ------------!
   iter = 0
   exitloop = 0
   do while(exitloop==0.and.cost_retrans_temp .lt. total_n_resistance.and. &
            falling_leaf_n.ge.0.0_r8.and.npp_to_spend.gt.0.0_r8)
      ! ------------------ Spend some C on removing N ------------!
      ! spend enough C to increase leaf C/N by 1 unit. 
      c_spent_retrans   = cost_retrans_temp * (falling_leaf_n - falling_leaf_c / &
                          (falling_leaf_cn + 1.0_r8))
      ! don't spend more C than you have  
      c_spent_retrans   = min(npp_to_spend_temp, c_spent_retrans) 
      ! N extracted, per this amount of C expenditure
      leaf_n_ext        = c_spent_retrans / cost_retrans_temp     
      ! Do not empty N pool 
      leaf_n_ext        = min(falling_leaf_n, leaf_n_ext)    
      !How much C do you need to account for the N that got taken up? 
      c_accounted_retrans = leaf_n_ext * plantCN * (1.0_r8 + grperc)      

      ! ------------------ Update leafCN, recalculate costs ------------!
      falling_leaf_n    = falling_leaf_n - leaf_n_ext          ! remove N from falling leaves pool 
      if(falling_leaf_n.gt.0.0_r8)then
         falling_leaf_cn   = falling_leaf_c/falling_leaf_n     ! C/N ratio
         cost_retrans_temp = kresorb /((1.0_r8/falling_leaf_cn)**1.3_r8) ! cost function. PARAMETER
      else
         exitloop=1
      endif 
 
      ! ------------------ Accumulate total fluxes ------------!
      total_c_spent_retrans     = total_c_spent_retrans + c_spent_retrans 
      total_c_accounted_retrans = total_c_accounted_retrans + c_accounted_retrans 
      paid_for_n_retrans    = paid_for_n_retrans    + leaf_n_ext
      npp_to_spend_temp     = npp_to_spend_temp     - c_spent_retrans  - c_accounted_retrans
      iter = iter+1
   
      ! run out of C or N
      if(npp_to_spend_temp.le.0.0_r8)then
         exitloop=1
         ! if we made a solving error on this (expenditure and n uptake should 
         ! really be solved simultaneously)
         ! then remove the error from the expenditure. This changes the notional cost, 
         ! but only by a bit and prevents cpool errors. 

         total_c_spent_retrans  = total_c_spent_retrans + npp_to_spend_temp 
      endif 
      ! leaf CN is too high
      if(falling_leaf_cn.ge.max_falling_leaf_cn)then
         exitloop=1
      endif
      ! safety check to prevent hanging code
      if(iter.ge.150)then
          exitloop=1
      endif 
   end do

 end subroutine fun_retranslocation

!==========================================================================

!==========================================================================

 subroutine fun_retranslocation_p(p,dt,npp_to_spend_p,total_falling_leaf_c,         &
               total_falling_leaf_p, total_p_resistance, total_c_spent_retrans, &
               total_c_accounted_retrans, free_p_retrans, paid_for_p_retrans,   &
               target_leafcp, grperc, plantCP,smallValue,big_cost)
!
! Description:
! This subroutine (should it be a function?) calculates the amount of P absorbed and C spent 
! during retranslocation. 
! Renato Braghiere.May 2020. 
! !USES:
  implicit none 

! !ARGUMENTS:
  real(r8), intent(IN) :: total_falling_leaf_c  ! INPUT  gC/m2/timestep
  real(r8), intent(IN) :: total_falling_leaf_p  ! INPUT  gC/m2/timestep
  real(r8), intent(IN) :: total_p_resistance    ! INPUT  gC/gP
  real(r8), intent(IN) :: npp_to_spend_p        ! INPUT  gP/m2/timestep
  real(r8), intent(IN) :: target_leafcp         ! INPUT  gC/gP
  real(r8), intent(IN) :: dt                    ! INPUT  seconds
  real(r8), intent(IN) :: grperc                ! INPUT growth respiration fraction
  real(r8), intent(IN) :: plantCP               ! INPUT plant CP ratio
  integer, intent(IN)  :: p                     ! INPUT  patch index
  real(r8), intent(IN) :: big_cost              !  An arbitrary large cost (gC/gN).
  real(r8), intent(IN) :: smallValue            !  A small number.

  real(r8), intent(OUT) :: total_c_spent_retrans     ! OUTPUT gC/m2/timestep
  real(r8), intent(OUT) :: total_c_accounted_retrans ! OUTPUT gC/m2/timestep
  real(r8), intent(OUT) :: paid_for_p_retrans        ! OUTPUT gP/m2/timestep
  real(r8), intent(OUT) :: free_p_retrans            ! OUTPUT gP/m2/timestep

  !
  ! !LOCAL VARIABLES:
  real(r8) :: kresorb               ! INTERNAL used factor
  real(r8) :: falling_leaf_c        ! INTERNAL gC/m2/timestep
  real(r8) :: falling_leaf_p        ! INTERNAL gP/m2/timestep
  real(r8) :: falling_leaf_cp       ! INTERNAL gC/gP
  real(r8) :: cost_retrans_temp     ! INTERNAL gC/gP
  real(r8) :: leaf_p_ext            ! INTERNAL gN/m2/timestep
  real(r8) :: c_spent_retrans       ! INTERNAL gC/m2/timestep
  real(r8) :: c_accounted_retrans   ! INTERNAL gC/m2/timestep
  real(r8) :: npp_to_spend_temp     ! INTERNAL gC/m2/timestep
  real(r8) :: max_falling_leaf_cp   ! INTERNAL gC/gP
  real(r8) :: min_falling_leaf_cp   ! INTERNAL gC/gP
  real(r8) :: cost_escalation       ! INTERNAL cost function parameter
  integer  :: iter                  ! INTERNAL
  integer  :: exitloop              ! INTERNAL
  ! ------------------------------------------------------------------------------- 




   ! ------------------ Initialize total fluxes. ------------------!
   total_c_spent_retrans = 0.0_r8
   total_c_accounted_retrans = 0.0_r8
   c_accounted_retrans   = 0.0_r8
   paid_for_p_retrans    = 0.0_r8
   npp_to_spend_temp     = npp_to_spend_p

   ! ------------------ Initial C and P pools in falling leaves. ------------------!
   falling_leaf_c       =  total_falling_leaf_c      
   falling_leaf_p       =  total_falling_leaf_p 

   !  ------------------ PARAMETERS ------------------ 
   max_falling_leaf_cp = target_leafcp * 3.0_r8 
   min_falling_leaf_cp = target_leafcp * 1.5_r8
   cost_escalation     = 1.3_r8

   !  ------------------ Free uptake ------------------ 
   free_p_retrans  = max(falling_leaf_p -  (falling_leaf_c/min_falling_leaf_cp),0.0_r8)
   falling_leaf_p = falling_leaf_p -  free_p_retrans 

   ! ------------------ Initial CP ratio and costs ------------------! 
   falling_leaf_cp      = falling_leaf_c/falling_leaf_p 
   kresorb = (1.0_r8/target_leafcp)
   cost_retrans_temp = kresorb /((1.0_r8/falling_leaf_cp)**cost_escalation) ! cost function. PARAMETER
   cost_retrans_temp =  cost_retrans_temp! cost function. PARAMETER

  !kresorb = 0.005 !From Allen et al. (2020)
  !if (total_falling_leaf_p  > smallValue) then
  ! cost_retrans_temp    = kresorb / falling_leaf_p 
  !else
!   Little P available. Set cost to an arbitrary high value.
  ! cost_retrans_temp = big_cost
  !end if
 
  ! ------------------ Iteration loops to figure out extraction limit ------------!
   iter = 0
   exitloop = 0
   do while(exitloop==0.and.cost_retrans_temp .lt. total_p_resistance.and. &
            falling_leaf_p.ge.0.0_r8.and.npp_to_spend_p.gt.0.0_r8)
      ! ------------------ Spend some C on removing P ------------!
      ! spend enough C to increase leaf C/P by 1 unit. 
      c_spent_retrans   = cost_retrans_temp * (falling_leaf_p - falling_leaf_c/ &
                          (falling_leaf_cp + 1.0_r8))
      ! don't spend more C than you have  
      c_spent_retrans   = min(npp_to_spend_temp, c_spent_retrans) 
      ! N extracted, per this amount of C expenditure
      leaf_p_ext        = c_spent_retrans / cost_retrans_temp     
      ! Do not empty N pool 
      leaf_p_ext        = min(falling_leaf_p, leaf_p_ext)    
      !How much C do you need to account for the N that got taken up? 
      c_accounted_retrans = leaf_p_ext * plantCP * (1.0_r8 + grperc)      

      ! ------------------ Update leafCP, recalculate costs ------------!
      falling_leaf_p    = falling_leaf_p - leaf_p_ext          ! remove P from falling leaves pool 
      if(falling_leaf_p.gt.0.0_r8)then
         falling_leaf_cp   = falling_leaf_c/falling_leaf_p     ! C/P ratio
         cost_retrans_temp = kresorb /((1.0_r8/falling_leaf_cp)**cost_escalation) ! cost function. PARAMETER
         cost_retrans_temp =  cost_retrans_temp! cost function. PARAMETER
         !if (total_falling_leaf_p  .gt. smallValue) then
         !  cost_retrans_temp    = kresorb / total_falling_leaf_p 
         !else
         !   Little P available. Set cost to an arbitrary high value.
         !  cost_retrans_temp = big_cost
         !end if
      else
         exitloop=1
      endif 
 
      ! ------------------ Accumulate total fluxes ------------!
      total_c_spent_retrans     = total_c_spent_retrans + c_spent_retrans 
      total_c_accounted_retrans = total_c_accounted_retrans + c_accounted_retrans 
      paid_for_p_retrans    = paid_for_p_retrans    + leaf_p_ext
      npp_to_spend_temp     = npp_to_spend_temp     - c_spent_retrans  - c_accounted_retrans
      iter = iter+1
   
      ! run out of C or P
      if(npp_to_spend_temp.le.0.0_r8)then
         exitloop=1
         ! if we made a solving error on this (expenditure and p uptake should 
         ! really be solved simultaneously)
         ! then remove the error from the expenditure. This changes the notional cost, 
         ! but only by a bit and prevents cpool errors. 

         total_c_spent_retrans  = total_c_spent_retrans + npp_to_spend_temp 
      endif 
      ! leaf CN is too high
      if(falling_leaf_cp.ge.max_falling_leaf_cp)then
         exitloop=1
      endif
      ! safety check to prevent hanging code
      if(iter.ge.150)then
          exitloop=1
      endif 
   end do

 end subroutine fun_retranslocation_p


!==========================================================================
end module CNFUNMod 
