//
//  CLIPTextModel.swift
//  CLIP-Finder2
//
//  Created by Fabio Guzman on 27/06/24.
//

//import CoreML
//
//class CLIPTextModel {
//    private var model: clip_text?
//    
//    init() {
//        loadModel()
//    }
//    
//    private func loadModel() {
//        do {
//            model = try clip_text(configuration: MLModelConfiguration())
//            print("CLIP text model loaded successfully.")
//        } catch {
//            print("Failed to load CLIP text model: \(error)")
//        }
//    }
//    
//    func performInference(tokens: [Int32]) -> MLMultiArray? {
//        guard let model = model else {
//            print("CLIP text model is not loaded.")
//            return nil
//        }
//        
//        do {
//            // Crear un MLMultiArray con los tokens
//            let inputArray = try MLMultiArray(shape: [1, 77] as [NSNumber], dataType: .int32)
//            for (index, token) in tokens.enumerated() {
//                inputArray[index] = NSNumber(value: token)
//            }
//            
//            // Realizar la predicción
//            let prediction = try model.prediction(input_text: inputArray)
//            
//            print("CLIP text model prediction successful.")
//            return prediction.featureValue(for: "var_475")?.multiArrayValue
//        } catch {
//            print("Failed to perform CLIP text model inference: \(error)")
//            return nil
//        }
//    }
//}

import CoreML

enum CLIPTextModelError: Error {
    case modelFileNotFound
    case modelNotLoaded
    case predictionFailed
}

final class CLIPTextModel {
    var model: MLModel?
    private var configuration: MLModelConfiguration
    
    init() {
        self.configuration = MLModelConfiguration()
        self.configuration.computeUnits = .all // Por defecto, usa todas las unidades de cómputo
        
        Task {
            do {
                try await loadModel()
            } catch {
                print("Failed to load CLIP text model: \(error)")
            }
        }
    }
    
    func setProcessingUnit(_ unit: MLComputeUnits) {
        configuration.computeUnits = unit
    }
    
    func reloadModel() async {
        do {
            try await loadModel()
        } catch {
            print("Failed to reload CLIP text model: \(error)")
        }
    }
    
    private func loadModel() async throws {
        guard let modelURL = Bundle.main.url(forResource: "clip_text", withExtension: "mlmodelc") else {
            print("Current bundle URL: \(Bundle.main.bundleURL)")
            throw CLIPTextModelError.modelFileNotFound
        }
        
        model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        print("CLIP text model loaded successfully.")
    }
    
    func performInference(_ tokens: [Int32]) async throws -> MLMultiArray? {
        guard let model = model else {
            throw CLIPTextModelError.modelNotLoaded
        }
        
        do {
            // Crear un MLMultiArray con los tokens
            let inputArray = try MLMultiArray(shape: [1, 77] as [NSNumber], dataType: .int32)
            for (index, token) in tokens.enumerated() {
                inputArray[index] = NSNumber(value: token)
            }
            
            // Crear el input para el modelo
            let input = TextInputFeatureProvider(input_text: inputArray)
            
            // Realizar la predicción
            let outputFeatures = try await model.prediction(from: input)
            
            // Extraer el MLMultiArray del resultado
            if let multiArray = outputFeatures.featureValue(for: "var_475")?.multiArrayValue {
                return multiArray
            } else {
                throw CLIPTextModelError.predictionFailed
            }
        } catch {
            print("Failed to perform CLIP text inference: \(error)")
            throw error
        }
    }
}

class TextInputFeatureProvider : MLFeatureProvider {
    var input_text: MLMultiArray

    var featureNames: Set<String> {
        get {
            return ["input_text"]
        }
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        if (featureName == "input_text") {
            return MLFeatureValue(multiArray: input_text)
        }
        return nil
    }
    
    init(input_text: MLMultiArray) {
        self.input_text = input_text
    }

    convenience init(input_text: MLShapedArray<Int32>) {
        self.init(input_text: MLMultiArray(input_text))
    }
}
