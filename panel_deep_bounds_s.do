clear all
cls
*******************************************************************************
**# 0. Directorio
*******************************************************************************

if ("`c(username)'" == "gilmar") { // Gilmar Belzu
 global path "C/Users/gilmar/Documents/Aru2025/Investigaciones/Panel"
 global data  "$path/_data"
 global out  "$path/_out"
 global temp "$path/_temp"
}
if ("`c(username)'" == "Carlos") { // Carlos Pantoja (PC-ARU)
 global path "C:\Users\Carlos\OneDrive - aru.org.bo\General - Arusearch\Contrucción de un Panel Sintético a partir de las encuestas de hogares\Procesamiento de datos"
 global data  "$path/_data"
 global out  "$path/_out"
 global temp "$path/_temp"
}


*******************************************************************************
**# 1. Importamos base de datos y nos quedamos con las variables que usaremos 
*******************************************************************************

// Procesar encuesta EH2019
use "$data\raw\EH2019_Persona.dta", clear
keep s02a_04c yhogpc s02a_03 s02a_05 estrato factor folio upm s02a_02 area depto niv_ed_g z
save "$data\Processed/EH2019_Persona.dta", replace


// Procesar encuesta EH2023
use "$data\raw\EH2023_Persona.dta", clear
keep s01a_04c yhogpc s01a_03 s01a_05 estrato factor folio upm s01a_02 area depto niv_ed_g z
save "$data\Processed/EH2023_Persona.dta", replace


***********************************************************************
**# 2. Armonizamos las bases de datos con iecodebook
*******************************************************************************

	* Usamos el comando template para obtener los codebooks de las bases de datos 

*iecodebook template $data\Processed\EH2019_Persona.dta" "$data\Processed\EH2023_Persona.dta" ///
       using "$path\_codebook\armo_2015_2023.xlsx" ///
       , surveys( 2019 2023)

	   
	* Luego de haber ajustado las variables en el excel procedemos a aplicar los ajustes a las bases con comando append
	   
iecodebook append "$data\Processed\EH2015_Persona.dta" "$data\Processed\EH2019_Persona.dta" "$data\Processed\EH2020_Persona.dta" "$data\Processed\EH2021_Persona.dta" "$data\Processed\EH2022_Persona.dta" "$data\Processed\EH2023_Persona.dta" ///
       using "$path\_codebook\armo_2015_2023.xlsx" ///
       , surveys(2019 2023) clear 
	   
	   
		
	* Finalmente guardamos la base que usaremos 
rename survey year
rename s02a_05 parentco
rename factor factor_ine
rename s02a_03 edad
	save "$data/processed/EH_armo_final.dta", replace

*/
 
*******************************************************************************
**# 3. Datos y salida
*******************************************************************************

	use "$data/processed/EH_armo_final.dta", clear				// especificar la ruta para cargar los datos

	decode year, gen(year_s)
	drop year
	rename year_s year
	
	gen mujer=0
	replace mujer=1 if s02a_02==2
	*** Entradas de regresión y otros parámetros
	gen birth_year = s02a_04c
	local indvars = "birth_year mujer area depto i.niv_ed_g" 			// definir una lista de variables explicativas que son invariantes en el tiempo
	local depvar = "yhogpc"			// definir la variable de resultado

	*** Rango de edad
	local agevar = "edad"			// definir la variable que identifica la edad del jefe del hogar en años
	scalar min_age = 20			// elegir un valor tal que la estabilidad de la muestra sea óptima
	scalar max_age = 60

	*** Años de la encuesta
	local yearvar = "year"			// definir la variable que identifica las diferentes rondas o años de la encuesta
	local y1 = "2019"				// especificar el primer año o ronda para el panel sintético (debe ser un valor de yearvar)
	local y2 = "2023"				// especificar el segundo año o ronda para el panel sintético (debe ser un valor de yearvar)

	*** Otros parámetros

	keep if parentco == 1 
	local idvar = "folio" 			// definir la variable que identifica de manera única a los hogares
	local draws = "1000"			// número de simulaciones aleatorias de residuos para estimar los límites superiores de las transiciones [límites]
	local seed = "12345"				// semilla para la simulación aleatoria [límites]

	*** Configuración de la encuesta
	svyset [pw=factor_ine], strata(estrato)			// especificar el diseño de la encuesta, como conglomerados y ponderaciones; se usan en regresiones y en la agregación de probabilidades de transición
	local weight = "factor_ine"			// especificar la variable que indica las ponderaciones

	*** Línea de pobreza
	local povline1 = "838.2789" 			// definir la línea de pobreza para el primer año/ronda; asegurar que esté en la misma unidad que la variable de resultado
	local povline2 = "865.0668" 			// definir la línea de pobreza para el segundo año/ronda; asegurar que esté en la misma unidad que la variable de resultado


*******************************************************************************
**# 4. Programa
*******************************************************************************

*** PRESERVAR datos para deshacer las restricciones de rango de edad y eliminaciones para el sorteo aleatorio de residuos

preserve

*** Configurar archivos de salida y macro de años/rondas de encuesta
matrix A = (0)
frmttable using synpan_tables`y1'`y2', statmat(A) sfmt(g) title("Estimaciones de movilidad de pobreza - panel sintético") titlfont(fs16) replace

levelsof `yearvar', local(year)		// almacenar los diferentes valores de años en la macro local 'year'

*** Output de regresión 

outreg, clear

foreach y in `y1' `y2'	{
	
	drop if (`yearvar' == `y' & `agevar' < min_age) | (`yearvar' == `y' & `agevar' > max_age)
	
	svy: reg `depvar' `indvars' if `yearvar' == `y'
	
	outreg using synpan_regr`y1'`y2', se starlevels(10 5 1) summstat(r2\N) summtitle("R2"\"N") summdec(3 0) title("Modelo de ingresos panel sintético" \ "Variable dependiente: `depvar'") ctitles("","`y'") note("insertar nota aquí") landscape merge replace

	restore, preserve
	
	}

	
***** LOOP para producir tablas para diferentes combinaciones de años ********************************************************************

*** Inicio del bucle para estimaciones de límites

				
	if `y1' < `y2'	{
		
		scalar pline`y1' = `povline1' 
		scalar pline`y2' = `povline2' 	
		
		**** ELIMINAR OBSERVACIONES FUERA DEL RANGO DE EDAD

		local diff = `y2'-`y1'

		drop if (`yearvar' == `y1' & `agevar' < min_age) | (`yearvar' == `y1' & `agevar' > max_age)
		drop if (`yearvar' == `y2' & `agevar' < (min_age +`diff')) | (`yearvar' == `y2' & `agevar' > (max_age +`diff' ))

		**** MODELO DE INGRESOS *************************************************************
		**** ESTIMACIONES DE LÍMITES DE PROBABILIDADES CONDICIONALES E INCONDICIONALES
			
		*** regresiones para obtener entradas para cálculos de límites

		svy: reg `depvar' `indvars' if `yearvar' == `y1'	
		
		predict res`y1' if e(sample), residuals								// residuos para el año 1
		predict fitinc`y1' if e(sample) == 0 & `yearvar' ==`y2', xb 		// ingresos ajustados para el año 2
		
		sum res`y1' if `yearvar' == `y1' [aw=`weight']
		scalar sd_res`y1' = r(sd)
		
		svy: reg `depvar' `indvars' if `yearvar' == `y2' 

		predict res`y2' if e(sample), residuals						// residuos para el año 2
		sum res`y2' if `yearvar' == `y2' [aw=`weight']
		scalar sd_res`y2' = r(sd)

		
		scalar gamma = sd_res`y1'/sd_res`y2'						// entrada para los ingresos predichos de límite inferior; gamma se utiliza para escalar los residuos del año 2; ver ecuaciones 11, 12 y 18
		
		gen p`y2' = .												// estado de pobreza en `y2' para las observaciones de `y2', usando la observación real
		replace p`y2' = 0 if `depvar' > pline`y2' & `yearvar' == `y2'				
		replace p`y2' = 1 if `depvar' <= pline`y2' & `yearvar' == `y2'

		***** LÍMITE SUPERIOR DE MOVILIDAD (rho = 0) **********************
		
		*** sorteo aleatorio de residuos del año 1				// nota que esto solo funciona si los datos están ordenados y `y1' es el primer año
		set seed `seed'												
		
		drop if `yearvar'<`y1'			
		sort `yearvar'
		count if `yearvar' == `y1'
		scalar obs`y1' = r(N)
		
		*** Bucle sobre R sorteos para producir cuatro variables por sorteo, una para cada transición de pobreza

		
		forvalues i = 1(1)`draws'	{													
			
			gen res`y1'_rnd = res`y1'[runiformint(1,obs`y1')] if `yearvar' == `y2'				// el sorteo aleatorio real, asignando una observación aleatoria del rango [1,N(y1)] a cada observación de `y2'

			*** Predecir ingresos de `y1' para observaciones de `y2' (límite superior) - ecuación 17 DLLM, rho = 0
			gen predinc`y1'_UB_`i' = fitinc`y1'+res`y1'_rnd if `yearvar' == `y2'					

			*** Calcular el estado de pobreza predicho en `y1' para observaciones de `y2' (límite superior)
			gen p`y1'_UB_`i' = .	
			replace p`y1'_UB_`i' = 0 if predinc`y1'_UB_`i' > pline`y1' & `yearvar' == `y2'		
			replace p`y1'_UB_`i' = 1 if predinc`y1'_UB_`i' <= pline`y1' & `yearvar' == `y2'

			*** Transiciones predichas (nivel del hogar)
			
			* P-NP UB - ecuación 5 DLLM
			gen p`y1'np`y2'_UB_`i' = .
			replace p`y1'np`y2'_UB_`i' = 0 if `yearvar' == `y2'
			replace p`y1'np`y2'_UB_`i' = 1 if `yearvar' == `y2' & p`y1'_UB_`i' == 1 & p`y2' == 0		
			
			* NP-P UB - ecuación 6 DLLM
			gen np`y1'p`y2'_UB_`i' = .
			replace np`y1'p`y2'_UB_`i' = 0 if `yearvar' == `y2'
			replace np`y1'p`y2'_UB_`i' = 1 if `yearvar' == `y2' & p`y1'_UB_`i' == 0 & p`y2' == 1		

			* NP-NP LB - ecuación 9 DLLM; nota: los límites inferiores de inmovilidad se derivan de los límites superiores de movilidad
			gen np`y1'np`y2'_LB_`i' = .													
			replace np`y1'np`y2'_LB_`i' = (1-p`y2')-p`y1'np`y2'_UB_`i' if `yearvar' == `y2'			

			* P-P LB - ecuación 10 DLLM; nota: los límites inferiores de inmovilidad se derivan de los límites superiores de movilidad
			gen p`y1'p`y2'_LB_`i' = .												
			replace p`y1'p`y2'_LB_`i' = p`y2'-np`y1'p`y2'_UB_`i' if `yearvar' == `y2'					
			
			drop res`y1'_rnd predinc`y1'_UB_`i' p`y1'_UB_`i'	// eliminar variables para que puedan generarse nuevamente para el próximo sorteo
		
			}
			
		*** Generar promedios sobre R sorteos para las transiciones a nivel de hogar
		
		egen p`y1'np`y2'_UB = rowmean(p`y1'np`y2'_UB_*) if `yearvar' == `y2' 
		egen np`y1'p`y2'_UB = rowmean(np`y1'p`y2'_UB_*) if `yearvar' == `y2'
		egen np`y1'np`y2'_LB = rowmean(np`y1'np`y2'_LB_*) if `yearvar' == `y2'
		egen p`y1'p`y2'_LB = rowmean(p`y1'p`y2'_LB_*) if `yearvar' == `y2'
			
		*** Estimar transiciones agregadas tomando el promedio ponderado de las probabilidades de los hogares, almacenar esto en la matriz UB 
		
		svy: mean p`y1'p`y2'_LB p`y1'np`y2'_UB np`y1'p`y2'_UB np`y1'np`y2'_LB  	// estimar el promedio de las cuatro probabilidades a nivel de hogar generadas, en el orden de la tabla
		
		matrix UB = e(b)	
		scalar N_agg = e(N)

		drop p`y1'p`y2'_LB_* p`y1'np`y2'_UB_* np`y1'p`y2'_UB_* np`y1'np`y2'_LB_*  // eliminar las probabilidades de transición de cada sorteo, no es necesario mantenerlas
			
		assert round(UB[1,1]+UB[1,2]+UB[1,3]+UB[1,4],0.001) == 1
		
		matrix list UB								// la matriz UB contiene los cuatro promedios de las probabilidades de transición incondicionales 
		
		*** Generar matrices para mostrar resultados de probabilidades incondicionales (UP) y condicionales (CP)

		matrix define UP = J(6,2,.)
		matrix rownames UP = "Pobre, pobre" "Pobre, no pobre" "No pobre, pobre" "No pobre, no pobre" "." "N"
		matrix colnames UP = "Límite Inferior" "Límite Superior"
		
		// nota que los límites inferiores para la inmovilidad se muestran en la tabla en la columna para los límites superiores de movilidad (col2)
		matrix UP[1,2] = UB'				// colocar la transposición de UB en la columna derecha de la tabla	
		matrix UP[6,2] = N_agg
		
		matrix define CP = J(6,2,.)
		matrix rownames CP = "Pobre a pobre" "Pobre a no pobre" "No pobre a pobre" "No pobre a no pobre" "." "N"
		matrix colnames CP = "Límite Inferior" "Límite Superior"
		
		scalar p1_UB = UB[1,1]+UB[1,2]		// probabilidad de ser pobre en el año 1
		scalar np1_UB = UB[1,3]+UB[1,4]		// probabilidad de no ser pobre en el año 1
		
		// las probabilidades condicionales son iguales a las probabilidades incondicionales divididas por la probabilidad general de ser pobre o no pobre en el año 1


		matrix CP[1,2] = UP[1,2]/p1_UB 		// pobre en el año 2, dado que fue pobre en el año 1
		matrix CP[2,2] = UP[2,2]/p1_UB		// no pobre en el año 2, dado que fue pobre en el año 1
		matrix CP[3,2] = UP[3,2]/np1_UB		// pobre en el año 2, dado que no fue pobre en el año 1
		matrix CP[4,2] = UP[4,2]/np1_UB		// no pobre en el año 2, dado que no fue pobre en el año 1

		matrix CP[6,2] = N_agg
		
		******* LÍMITE INFERIOR DE MOVILIDAD (rho = 1)**********************************
		
		*** Predecir ingresos de `y1' para observaciones de `y2' (límite inferior) - ecuación 18 DLLM, rho = 1
		gen predinc`y1'_LB = fitinc`y1'+gamma*res`y2' if `yearvar' == `y2'					

		*** Predecir el estado de pobreza en `y1' para observaciones de `y2' (límite inferior)
		gen p`y1'_LB = .		
		replace p`y1'_LB = 0 if predinc`y1'_LB > pline`y1' & `yearvar' == `y2'		
		replace p`y1'_LB = 1 if predinc`y1'_LB <= pline`y1' & `yearvar' == `y2'

		*** Transiciones predichas (nivel del hogar)
		
		* P-NP LB - ecuación 11 DLLM
		gen byte p`y1'np`y2'_LB = .
		replace p`y1'np`y2'_LB = 0 if `yearvar' == `y2'
		replace p`y1'np`y2'_LB = 1 if p`y1'_LB == 1 & p`y2' == 0 & `yearvar' == `y2'		

		* NP-P LB - ecuación 12 DLLM
		gen byte np`y1'p`y2'_LB = .
		replace np`y1'p`y2'_LB = 0 if `yearvar' == `y2'
		replace np`y1'p`y2'_LB = 1 if p`y1'_LB == 0 & p`y2' == 1 & `yearvar' == `y2'		
		
		* NP-NP UB - ecuación 15 DLLM; nota: los límites superiores de inmovilidad se derivan de los límites inferiores de movilidad
		gen byte np`y1'np`y2'_UB = .														
		replace np`y1'np`y2'_UB = (1-p`y2')-p`y1'np`y2'_LB if `yearvar' == `y2'			

		* P-P UB - ecuación 16 DLLM
		gen byte p`y1'p`y2'_UB = .												
		replace p`y1'p`y2'_UB = p`y2'-np`y1'p`y2'_LB if `yearvar' == `y2'					

		*** Estimar transiciones agregadas tomando el promedio ponderado de las probabilidades de los hogares

		
		svy: mean p`y1'p`y2'_UB p`y1'np`y2'_LB np`y1'p`y2'_LB np`y1'np`y2'_UB  	// estimar el promedio de las cuatro probabilidades a nivel de hogar generadas

		matrix LB = e(b)	
			
		assert round(LB[1,1]+LB[1,2]+LB[1,3]+LB[1,4],0.001) == 1	// una verificación para asegurar que las probabilidades sumen 1

		// nota que los límites superiores de inmovilidad se muestran en la tabla en la columna para los límites inferiores de movilidad (col 1)
		matrix UP[1,1] = LB'				// colocar la transposición de LB en la columna izquierda de la tabla	
		matrix UP[6,1] = e(N)
		
		scalar p1_LB = LB[1,1]+LB[1,2]				// probabilidad de ser pobre en el año 1
		scalar np1_LB = LB[1,3]+LB[1,4]				// probabilidad de no ser pobre en el año 1	
		
		matrix CP[1,1] = UP[1,1]/p1_LB				
		matrix CP[2,1] = UP[2,1]/p1_LB
		matrix CP[3,1] = UP[3,1]/np1_LB
		matrix CP[4,1] = UP[4,1]/np1_LB
		matrix CP[6,1] = e(N)		

		frmttable using synpan_tables`y1'`y2', statmat(UP) sdec(3\3\3\3\0\0) title("Estimaciones de límites `y1' - `y2'" \ "Probabilidades conjuntas no paramétricas") note("Estimado usando una línea de pobreza de `povline1' en el año 1 y `povline2' en el año 2." \ "Las filas muestran la fracción de la población en el rango de edad seleccionado que está en cada una de las cuatro categorías." \ "Por ejemplo, 'Pobre, pobre' indica la fracción que fue pobre en el año 1 y pobre en el año 2.") addtable replace

		frmttable using synpan_tables`y1'`y2', statmat(CP) sdec(3\3\3\3\0\0) title("Estimaciones de límites `y1' - `y2'" \ "Probabilidades condicionales no paramétricas") note("Estimado usando una línea de pobreza de `povline1' en el año 1 y `povline2' en el año 2." \ "Las filas muestran la probabilidad de cada uno de los cuatro estados. Por ejemplo," \ " 'Pobre a pobre' indica la probabilidad de ser pobre en el año 2, dado que el individuo también fue pobre en el año 1.") addtable replace
		
		keep `idvar' `yearvar' p`y1'np`y2'_UB np`y1'p`y2'_UB np`y1'np`y2'_LB p`y1'p`y2'_LB p`y1'np`y2'_LB np`y1'p`y2'_LB np`y1'np`y2'_UB p`y1'p`y2'_UB
		
		save synpan_povtran`y1'`y2', replace
		
		restore, preserve


		}



*******************************************************************************
**# 5. Guardado
*******************************************************************************


*** UNIR las probabilidades de transición estimadas a nivel de hogar de cada intervalo al conjunto de datos
*** GUARDAR el conjunto de datos como un panel sintético

	if `y1' < `y2'	{

		merge 1:1 `idvar' `yearvar' using synpan_povtran`y1'`y2', gen(_m`y1'`y2') assert(1 3)
		
		drop _m*
		
		erase synpan_povtran`y1'`y2'.dta
				
		}
		
	save synpan, replace

