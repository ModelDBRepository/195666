: Calcium ion accumulation with radial and longitudinal diffusion and pump

NEURON {
	THREADSAFE
  SUFFIX cdp
  USEION ca READ cao, cai, ica WRITE cai, ica
  RANGE ica_pmp
  GLOBAL vrat, TotalBuffer, TotalPump
    : vrat must be GLOBAL--see INITIAL block
    : however TotalBuffer and TotalPump may be RANGE
}

DEFINE Nannuli 3

UNITS {
  (mol)   = (1)
  (molar) = (1/liter)
  (mM)    = (millimolar)
  (um)    = (micron)
  (mA)    = (milliamp)
  FARADAY = (faraday)  (10000 coulomb)
  PI      = (pi)       (1)
}

PARAMETER {
  DCa   = 0.8 (um2/ms)
  k1buf = 100 (/mM-ms) : Yamada et al. 1989
  k2buf = 0.1 (/ms)
  TotalBuffer = 0.003  (mM)

  k1    = 1       (/mM-ms)
  k2    = 0.005   (/ms)
  k3    = 1       (/ms)
  k4    = 0.005   (/mM-ms)
  : to eliminate pump, set TotalPump to 0 in hoc
  TotalPump = 1e-11  (mol/cm2)
}

ASSIGNED {
  diam      (um)
  ica       (mA/cm2)
  ica_pmp   (mA/cm2)
  ica_pmp_last   (mA/cm2)
  parea     (um)     : pump area per unit length
  cai       (mM)
  cao       (mM)
  vrat[Nannuli]  (1) : dimensionless
                     : numeric value of vrat[i] equals the volume 
                     : of annulus i of a 1um diameter cylinder
                     : multiply by diam^2 to get volume per um length
  Kd        (/mM)
  B0        (mM)
}

CONSTANT { volo = 1e10 (um2) }

STATE {
  : ca[0] is equivalent to cai
  : ca[] are very small, so specify absolute tolerance
  : let it be ~1.5 - 2 orders of magnitude smaller than baseline level
  ca[Nannuli]       (mM) <1e-7>
  CaBuffer[Nannuli] (mM) <1e-5>
  Buffer[Nannuli]   (mM) <1e-5>
  pump              (mol/cm2) <1e-15>
  pumpca            (mol/cm2) <1e-15>
}

BREAKPOINT {
  SOLVE state METHOD sparse
  ica_pmp_last = ica_pmp
  ica = ica_pmp
}

LOCAL factors_done

INITIAL {
   if (factors_done == 0) {  : flag becomes 1 in the first segment
      factors_done = 1       :   all subsequent segments will have
      factors()              :   vrat = 0 unless vrat is GLOBAL
   }

  Kd = k1buf/k2buf
  B0 = TotalBuffer/(1 + Kd*cai)

  FROM i=0 TO Nannuli-1 {
    ca[i] = cai
    Buffer[i] = B0
    CaBuffer[i] = TotalBuffer - B0
  }

  parea = PI*diam

: Manually computed initalization of pump
: assumes that cai has been equal to cai0_ca_ion for a long time
:  pump = TotalPump/(1 + (cai*k1/k2))
:  pumpca = TotalPump - pump
: If possible, instead of using formulas to calculate pump and pumpca,
: let NEURON figure them out--just uncomment the following four statements
  ica=0
  ica_pmp = 0
  ica_pmp_last = 0
  SOLVE state STEADYSTATE sparse
: This requires that pump and pumpca be constrained by the CONSERVE
: statement in the STATE block.
: If there is a voltage-gated calcium current, 
: this is almost certainly the wrong initialization. 
: In such a case, first do an initialization run, then use SaveState
: On subsequent runs, restore the initial condition from the saved states.
}

LOCAL frat[Nannuli]  : scales the rate constants for model geometry
PROCEDURE factors() {
  LOCAL r, dr2
  r = 1/2                : starts at edge (half diam)
  dr2 = r/(Nannuli-1)/2  : full thickness of outermost annulus,
                         : half thickness of all other annuli
  vrat[0] = 0
  frat[0] = 2*r
  FROM i=0 TO Nannuli-2 {
    vrat[i] = vrat[i] + PI*(r-dr2/2)*2*dr2  : interior half
    r = r - dr2
    frat[i+1] = 2*PI*r/(2*dr2)  : outer radius of annulus
                                : div by distance between centers
    r = r - dr2
    vrat[i+1] = PI*(r+dr2/2)*2*dr2  : outer half of annulus
  }
}

LOCAL dsq, dsqvol  : can't define local variable in KINETIC block
                   :   or use in COMPARTMENT statement

KINETIC state {
  COMPARTMENT i, diam*diam*vrat[i] {ca CaBuffer Buffer}
  COMPARTMENT (1e10)*parea {pump pumpca}
  COMPARTMENT volo {cao}
  LONGITUDINAL_DIFFUSION i, DCa*diam*diam*vrat[i] {ca}

  :pump
  ~ ca[0] + pump <-> pumpca  (k1*parea*(1e10), k2*parea*(1e10))
  ~ pumpca <-> pump + cao    (k3*parea*(1e10), k4*parea*(1e10))
  CONSERVE pump + pumpca = TotalPump * parea * (1e10)
  ica_pmp = 2*FARADAY*(f_flux - b_flux)/parea

  : all currents except pump
  : ica is Ca efflux
  ~ ca[0] << (-(ica - ica_pmp_last)*PI*diam/(2*FARADAY))
  FROM i=0 TO Nannuli-2 {
    ~ ca[i] <-> ca[i+1]  (DCa*frat[i+1], DCa*frat[i+1])
  }
  dsq = diam*diam
  FROM i=0 TO Nannuli-1 {
    dsqvol = dsq*vrat[i]
    ~ ca[i] + Buffer[i] <-> CaBuffer[i]  (k1buf*dsqvol, k2buf*dsqvol)
  }
  cai = ca[0]
}
