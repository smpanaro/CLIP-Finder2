//
//  PhotoGalleryViewModel.swift
//  CLIP-Finder2
//
//  Created by Fabio Guzman on 24/06/24.
//

import SwiftUI
import Photos
import CoreML
import Combine
import MetalPerformanceShaders
import MetalPerformanceShadersGraph

import CoreVideo
import CoreImage

class PhotoGalleryViewModel: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var topPhotoIDs: [String] = []
    //private var model = DataModel()
    private var customTokenizer: CLIPTokenizer?
    private var clipTextModel: CLIPTextModel
    private var model: DataModel
    private var searchTask: Task<Void, Never>?
    @Published var isCameraActive = false
    @Published var isPaused = false
    var onFrameCaptured: ((CIImage) -> Void)?
//    let cameraManager = CameraManager()
    private var cameraManager: CameraManager
    @Published var processingProgress: Float = 0
    @Published var processedPhotosCount: Int = 0
    @Published var totalPhotosCount: Int = 0
    @Published var isProcessing: Bool = false
    
    private var updateTimer: Timer?

    
    init() {
        self.cameraManager = CameraManager()
        self.model = DataModel()
        self.clipTextModel = CLIPTextModel()
        setupTokenizer()
        setupCameraManager()
    }
    
    
//    private func setupCameraManager() {
//        cameraManager.onFrameCaptured = { [weak self] ciImage in
//            guard let self = self, self.isCameraActive else { return }
//            self.performImageSearch(from: ciImage)
//        }
//    }
    private func setupCameraManager() {
        cameraManager.onFrameCaptured = { [weak self] ciImage in
            guard let self = self, self.isCameraActive, !self.isPaused else { return }
//            self.performImageSearch(from: ciImage)
            Task {
                await self.performImageSearch(from: ciImage)
            }
            
            self.onFrameCaptured?(ciImage)
        }
    }
    
    func startCamera() {
        isCameraActive = true
        isPaused = false
        cameraManager.startRunning()
    }

    func stopCamera() {
        isCameraActive = false
        isPaused = false
        cameraManager.stopRunning()
    }
    
    func pauseCamera() {
        isPaused = true
        cameraManager.pauseCapture()
    }

    func resumeCamera() {
        isPaused = false
        cameraManager.resumeCapture()
    }
    
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            cameraManager.pauseCapture()
        } else {
            cameraManager.resumeCapture()
        }
    }
    
    func getCameraSession() -> AVCaptureSession {
        return cameraManager.session
    }

    func focusCamera(at point: CGPoint) {
        cameraManager.focusAtPoint(point)
    }

    func switchCamera() {
        cameraManager.switchCamera()
        if isPaused {
            // Si estaba en pausa, captura un nuevo frame para actualizar la imagen
            cameraManager.resumeCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.cameraManager.pauseCapture()
            }
        }
        objectWillChange.send()
    }
    
    
    func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Camera access granted")
                } else {
                    print("Camera access denied")
                }
                completion(granted)
            }
        }
    }

    private func setupTokenizer() {
        guard let bpePath = Bundle.main.path(forResource: "bpe_simple_vocab_16e6", ofType: "txt") else {
            fatalError("No se pudo encontrar el archivo BPE en el bundle")
        }
        customTokenizer = CLIPTokenizer(bpePath: bpePath)
    }
    
    func processTextSearch(_ searchText: String) {
        // Cancelar la tarea de búsqueda anterior si existe
        searchTask?.cancel()
        
        // Crear una nueva tarea de búsqueda
        searchTask = Task {
            // Añadir un pequeño retraso para evitar búsquedas excesivas
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                performSearch(searchText)
            }
        }
    }

//    private func performSearch(_ searchText: String) {
//        guard let tokenizer = customTokenizer else {
//            print("Tokenizer not initialized")
//            return
//        }
//
//
//        let tokens = tokenizer.tokenize(texts: [searchText])
//
//        // Aquí puedes agregar la lógica para procesar los tokens y actualizar la vista
//        // Por ejemplo, podrías llamar a calculateAndPrintTopPhotoIDs() con estos tokens
//        if let textFeatures = clipTextModel.performInference(tokens: tokens[0]) {
////            print(textFeatures.toFloatArray())
//            let topIDs = calculateAndPrintTopPhotoIDs(textFeatures: textFeatures)
//            DispatchQueue.main.async {
//                self.topPhotoIDs = topIDs
//            }
//        } else {
//            print("Failed to get text features from CLIP text model")
//        }
//
//    }
    private func performSearch(_ searchText: String) {
        guard let tokenizer = customTokenizer else {
            print("Tokenizer not initialized")
            return
        }

        let tokens = tokenizer.tokenize(texts: [searchText])

        Task {
            do {
                if let textFeatures = try await clipTextModel.performInference(tokens[0]) {
                    let topIDs = calculateAndPrintTopPhotoIDs(textFeatures: textFeatures)
                    await MainActor.run {
                        self.topPhotoIDs = topIDs
                    }
                } else {
                    print("Failed to get text features from CLIP text model")
                }
            } catch {
                print("Error performing CLIP text inference: \(error)")
            }
        }
    }
    
//    func performImageSearch(from ciImage: CIImage) {
//        guard isCameraActive else { return }
//        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
//        let uiImage = UIImage(cgImage: cgImage)
//        
//        guard let pixelBuffer = Preprocessing.preprocessImage(uiImage, targetSize: CGSize(width: 256, height: 256)) else { return }
//        
//        guard let imageFeatures = model.performInference(pixelBuffer) else { return }
//        
//        let topIDs = calculateAndPrintTopPhotoIDs(textFeatures: imageFeatures)
//        DispatchQueue.main.async {
//            self.topPhotoIDs = topIDs
//        }
//    }
    func performImageSearch(from ciImage: CIImage) async {
        guard isCameraActive else { return }
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let pixelBuffer = Preprocessing.preprocessImage(uiImage, targetSize: CGSize(width: 256, height: 256)) else { return }
        
        do {
            if let imageFeatures = try await model.performInference(pixelBuffer) {
                let topIDs = calculateAndPrintTopPhotoIDs(textFeatures: imageFeatures)
                await MainActor.run {
                    self.topPhotoIDs = topIDs
                }
            } else {
                print("Inference returned nil.")
            }
        } catch {
            print("Error performing inference: \(error)")
        }
    }


    func requestPhotoLibraryAccess() {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                self.fetchPhotos()
            } else {
                print("Photo library access denied.")
            }
        }
    }

    
//    private func fetchPhotos() {
//        Task {
//            let fetchOptions = PHFetchOptions()
//            let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
//            
//            // Crear assets dentro del Task para evitar problemas de concurrencia
//            let assets = await withCheckedContinuation { continuation in
//                var assets: [PHAsset] = []
//                allPhotos.enumerateObjects { asset, _, _ in
//                    assets.append(asset)
//                }
//                continuation.resume(returning: assets)
//            }
//            
//            // Actualizar self.assets en el hilo principal
//            await MainActor.run {
//                self.assets = assets
//            }
//            
//            do {
//                let startTime = CFAbsoluteTimeGetCurrent()
//                try await self.processAndCachePhotos {
//                    let endTime = CFAbsoluteTimeGetCurrent()
//                    let timeElapsed = (endTime - startTime) * 1000 // Convertir a milisegundos
//                    print("Procesamiento y caché completados en \(String(format: "%.2f", timeElapsed)) ms")
//                }
//            } catch {
//                print("Error durante el procesamiento y caché de fotos: \(error)")
//            }
//        }
//    }

    private func fetchPhotos() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var assets: [PHAsset] = []
            allPhotos.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            DispatchQueue.main.async {
                self.assets = assets
//                self.processAndCachePhotos()
                profileAsync("processAndCachePhotos") { done in
                    self.processAndCachePhotos {
                        done()
                    }
                } completion: { time in
                    print("Procesamiento y caché completados en \(time) ms")
                }
            }
        }
    }

//    private func processAndCachePhotos() {
//        let imageManager = PHImageManager.default()
//        let options = PHImageRequestOptions()
//        options.isSynchronous = true
//        options.deliveryMode = .highQualityFormat
//
//        DispatchQueue.main.async {
//            let targetSize = CGSize(width: 256, height: 256)
//            
//            print("cache async")
//
//            for asset in self.assets {
//                let identifier = asset.localIdentifier
//
//                if let cachedVector = CoreDataManager.shared.fetchVector(for: identifier) {
//                    // CoreDataManager.shared.deleteAllData()
//                    // Handle the cached vector as needed
//                    print("ID: \(identifier), Vector: \(cachedVector.toFloatArray())")
//                } else {
//                    imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
//                        if let image = image, let pixelBuffer = Preprocessing.preprocessImage(image, targetSize: targetSize), let vector = self.model.performInference(pixelBuffer) {
//                            CoreDataManager.shared.saveVector(vector, for: identifier)
//                            // print("ID: \(identifier), Vector: \(vector.toFloatArray())")
//                        }
////                        if let dummyBuffer = self.createDummyWhitePixelBuffer(), let vector = self.model.performInference(dummyBuffer) {
////                            CoreDataManager.shared.saveVector(vector, for: identifier)
////                        }
//                    }
//                }
//            }
//            
//        }
//    }
  
// funcionando ok
    private func processAndCachePhotos(completion: @escaping () -> Void) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat

        DispatchQueue.global(qos: .userInitiated).async {
            let targetSize = CGSize(width: 256, height: 256)
            let totalPhotosCount = self.assets.count
            var localProcessedCount = 0
            let group = DispatchGroup()
            let countQueue = DispatchQueue(label: "com.yourapp.processedCountQueue")
            let backgroundContext = CoreDataManager.shared.backgroundContext()

            DispatchQueue.main.async {
                self.isProcessing = true
                self.totalPhotosCount = totalPhotosCount
                self.updateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    DispatchQueue.main.async {
                        countQueue.sync {
                            self.processedPhotosCount = localProcessedCount
                            self.processingProgress = Float(localProcessedCount) / Float(totalPhotosCount)
                        }
                    }
                }
            }

            for asset in self.assets {
                group.enter()
                let identifier = asset.localIdentifier

                if CoreDataManager.shared.fetchVector(for: identifier, in: backgroundContext) != nil {
                    countQueue.sync {
                        localProcessedCount += 1
                    }
                    group.leave()
                } else {
                    imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, _ in
                        guard let self = self else {
                            group.leave()
                            return
                        }

                        if let image = image, let pixelBuffer = Preprocessing.preprocessImage(image, targetSize: targetSize) {
                            let pixelBufferCopy = pixelBuffer
                            Task {
                                do {
                                    if let vector = try await self.model.performInference(pixelBufferCopy) {
                                        CoreDataManager.shared.saveVector(vector, for: identifier, in: backgroundContext)
                                    } else {
                                        print("Inference returned nil for asset \(identifier)")
                                    }
                                    countQueue.sync {
                                        localProcessedCount += 1
                                    }
                                } catch {
                                    print("Failed to perform inference: \(error)")
                                    countQueue.sync {
                                        localProcessedCount += 1
                                    }
                                }
                                group.leave()
                            }
                        } else {
                            countQueue.sync {
                                localProcessedCount += 1
                            }
                            group.leave()
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                self.updateTimer?.invalidate()
                countQueue.sync {
                    self.processedPhotosCount = localProcessedCount
                    self.processingProgress = 1.0
                }
                self.isProcessing = false
                completion()
            }
        }
    }

//    // funcion con profiler de prediction
//    private func processAndCachePhotos(completion: @escaping () -> Void) {
//        let imageManager = PHImageManager.default()
//        let options = PHImageRequestOptions()
//        options.isSynchronous = true
//        options.deliveryMode = .highQualityFormat
//
//        DispatchQueue.global(qos: .userInitiated).async {
//            let targetSize = CGSize(width: 256, height: 256)
//            let totalPhotosCount = self.assets.count
//            var localProcessedCount = 0
//            let group = DispatchGroup()
//            let countQueue = DispatchQueue(label: "com.yourapp.processedCountQueue")
//            let backgroundContext = CoreDataManager.shared.backgroundContext()
//
//            DispatchQueue.main.async {
//                self.isProcessing = true
//                self.totalPhotosCount = totalPhotosCount
//                self.updateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
//                    DispatchQueue.main.async {
//                        countQueue.sync {
//                            self.processedPhotosCount = localProcessedCount
//                            self.processingProgress = Float(localProcessedCount) / Float(totalPhotosCount)
//                        }
//                    }
//                }
//            }
//
//            for asset in self.assets {
//                group.enter()
//                let identifier = asset.localIdentifier
//
//                if CoreDataManager.shared.fetchVector(for: identifier, in: backgroundContext) != nil {
//                    countQueue.sync {
//                        localProcessedCount += 1
//                    }
//                    group.leave()
//                } else {
//                    imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, _ in
//                        guard let self = self else {
//                            group.leave()
//                            return
//                        }
//
//                        if let image = image, let pixelBuffer = Preprocessing.preprocessImage(image, targetSize: targetSize) {
//                            let pixelBufferCopy = pixelBuffer
//                            Task {
//                                do {
//                                    AsyncProfileModel("CLIP MCI Image Prediction") { done in
//                                        Task {
//                                            if let vector = try await self.model.performInference(pixelBufferCopy) {
//                                                CoreDataManager.shared.saveVector(vector, for: identifier, in: backgroundContext)
//                                                done()
//                                            } else {
//                                                print("Inference returned nil for asset \(identifier)")
//                                                done()
//                                            }
//                                        }
//                                    } storeIn: { time in
//                                        PerformanceStats.shared.addClipMCIImagePredictionTime(time)
//                                    }
//                                    
//                                    countQueue.sync {
//                                        localProcessedCount += 1
//                                    }
//                                } catch {
//                                    print("Failed to perform inference: \(error)")
//                                    countQueue.sync {
//                                        localProcessedCount += 1
//                                    }
//                                }
//                                group.leave()
//                            }
//                        } else {
//                            countQueue.sync {
//                                localProcessedCount += 1
//                            }
//                            group.leave()
//                        }
//                    }
//                }
//            }
//
//            group.notify(queue: .main) {
//                self.updateTimer?.invalidate()
//                countQueue.sync {
//                    self.processedPhotosCount = localProcessedCount
//                    self.processingProgress = 1.0
//                }
//                self.isProcessing = false
//                completion()
//            }
//        }
//    }


//    private func processAndCachePhotos(completion: @escaping () -> Void) {
//        let imageManager = PHImageManager.default()
//        let options = PHImageRequestOptions()
//        options.isSynchronous = true
//        options.deliveryMode = .highQualityFormat
////        options.deliveryMode = .fastFormat
////        options.isNetworkAccessAllowed = false
////        options.version = .current
//
//        DispatchQueue.global(qos: .userInitiated).async {
//            let targetSize = CGSize(width: 256, height: 256)
//            
//            print("cache async")
//
//            let totalPhotosCount = self.assets.count
//            var localProcessedCount = 0
//            let group = DispatchGroup()
//
//            // Iniciar un timer para actualizar la UI cada 3 segundos
//            DispatchQueue.main.async {
//                self.isProcessing = true
//                self.totalPhotosCount = totalPhotosCount
//                self.updateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
//                    DispatchQueue.main.async {
//                        self.processedPhotosCount = localProcessedCount
//                        self.processingProgress = Float(localProcessedCount) / Float(totalPhotosCount)
//                    }
//                }
//            }
//
//            for asset in self.assets {
//                group.enter()
//                let identifier = asset.localIdentifier
//
//                if CoreDataManager.shared.fetchVector(for: identifier) != nil {
//                    localProcessedCount += 1
//                    group.leave()
//                } else {
//                    imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
//                        if let image = image, let pixelBuffer = Preprocessing.preprocessImage(image, targetSize: targetSize), let vector = self.model.performInference(pixelBuffer) {
//                            CoreDataManager.shared.saveVector(vector, for: identifier)
//                        }
//                        localProcessedCount += 1
//                        group.leave()
//                    }
//                }
//            }
//
//            group.notify(queue: .main) {
//                self.updateTimer?.invalidate()
//                self.processedPhotosCount = localProcessedCount
//                self.processingProgress = 1.0
//                self.isProcessing = false
//                completion()
//            }
//        }
//    }
    
    
//    private actor ProgressTracker {
//        var processedCount: Int = 0
//        var totalCount: Int
//        
//        init(totalCount: Int) {
//            self.totalCount = totalCount
//        }
//        
//        func increment() -> (processedCount: Int, progress: Float) {
//            processedCount += 1
//            return (processedCount, Float(processedCount) / Float(totalCount))
//        }
//    }

//    private func processAndCachePhotos(completion: @escaping () -> Void) async throws {
//        let imageManager = PHImageManager.default()
//        let options = PHImageRequestOptions()
//        options.isSynchronous = true
//        options.deliveryMode = .highQualityFormat
//        let targetSize = CGSize(width: 256, height: 256)
//        
//        print("cache async")
//        let totalPhotosCount = self.assets.count
//        let progressTracker = ProgressTracker(totalCount: totalPhotosCount)
//        
//        await MainActor.run {
//            self.isProcessing = true
//            self.totalPhotosCount = totalPhotosCount
//        }
//        
//        try await withThrowingTaskGroup(of: Void.self) { group in
//            for asset in self.assets {
//                group.addTask {
//                    try Task.checkCancellation()
//                    let identifier = asset.localIdentifier
//                    if CoreDataManager.shared.fetchVector(for: identifier) == nil {
//                        let image = try await self.requestImage(from: imageManager, for: asset, targetSize: targetSize, options: options)
//                        if let pixelBuffer = Preprocessing.preprocessImage(image, targetSize: targetSize) {
//                            let vector = try await self.model.performInference(pixelBuffer)
//                            CoreDataManager.shared.saveVector(vector, for: identifier)
//                        }
//                    }
//                    let (processedCount, progress) = await progressTracker.increment()
//                    await MainActor.run {
//                        self.processedPhotosCount = processedCount
//                        self.processingProgress = progress
//                    }
//                }
//            }
//            
//            // Esperar a que todas las tareas se completen y propagar cualquier error
//            try await group.waitForAll()
//        }
//        
//        await MainActor.run {
//            self.processingProgress = 1.0
//            self.isProcessing = false
//            completion()
//        }
//    }
//    
//    private func requestImage(from imageManager: PHImageManager, for asset: PHAsset, targetSize: CGSize, options: PHImageRequestOptions) async throws -> UIImage {
//        return try await withCheckedThrowingContinuation { continuation in
//            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
//                if let error = info?[PHImageErrorKey] as? Error {
//                    continuation.resume(throwing: error)
//                } else if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
//                    continuation.resume(throwing: NSError(domain: "PHImageManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Image request was cancelled"]))
//                } else if let image = image {
//                    continuation.resume(returning: image)
//                } else {
//                    continuation.resume(throwing: NSError(domain: "PHImageManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"]))
//                }
//            }
//        }
//    }
    
    func reprocessPhotos() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Eliminar todos los datos
            CoreDataManager.shared.deleteAllData()
            
            // Procesar y cachear fotos
            DispatchQueue.main.async {
                profileAsync("processAndCachePhotos") { done in
                    self.processAndCachePhotos {
                        done()
                    }
                } completion: { time in
                    print("Procesamiento y caché completados en \(time) ms")
                    print("Avg CLIP MCI Image Prediction Time: \(PerformanceStats.shared.averageClipMCIImagePredictionTime()) ms")
                    print("Number of samples: \(PerformanceStats.shared.clipMCIImagePredictionTimes.count)")
                }
            }
            
        }
    }
//    func reprocessPhotos() {
//        Task {
//            do {
//                // Asumimos que deleteAllData() es una operación que puede llevar tiempo,
//                // así que la hacemos asíncrona y esperamos a que termine
//                try await CoreDataManager.shared.deleteAllData()
//                
//                do {
//                    let startTime = CFAbsoluteTimeGetCurrent()
//                    try await self.processAndCachePhotos {
//                        let endTime = CFAbsoluteTimeGetCurrent()
//                        let timeElapsed = (endTime - startTime) * 1000 // Convertir a milisegundos
//                        print("Procesamiento y caché completados en \(String(format: "%.2f", timeElapsed)) ms")
//                    }
//                } catch {
//                    print("Error durante el procesamiento y caché de fotos: \(error)")
//                }
//            } catch {
//                print("Error durante el reprocesamiento de fotos: \(error)")
//            }
//        }
//    }

    
    private func createDummyWhitePixelBuffer(width: Int = 256, height: Int = 256) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32BGRA,
                                         attributes,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("Failed to create CVPixelBuffer")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: rgbColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            print("Failed to create CGContext")
            return nil
        }
        
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
    
//    private func calculateAndPrintTopPhotoIDs_cpu() {
//        // Obtener todos los vectores de fotos e IDs desde Core Data
//        let photoVectorsWithIDs = CoreDataManager.shared.fetchAllPhotoVectors()
//        let photoVectors = photoVectorsWithIDs.map { $0.vector }
//        let photoIDs = photoVectorsWithIDs.map { $0.id }
//        
//        // Preparar los datos de entrada
//        var inputVals = [Float](repeating: 0, count: photoVectors.count * 512)
//        for (i, vector) in photoVectors.enumerated() {
//            let floatArray = vector.toFloatArray()
//            for j in 0..<512 {
//                inputVals[i * 512 + j] = floatArray[j]
//            }
//        }
//
//        // Crear el vector de características de texto
//        let textFeatures = [Float](repeating: 1.0 / 512.0, count: 512)
//        
//        // Calcular similitudes
//        var similarities = [Float](repeating: 0, count: photoVectors.count)
//        for i in 0..<photoVectors.count {
//            var similarity: Float = 0.0
//            for j in 0..<512 {
//                similarity += inputVals[i * 512 + j] * textFeatures[j]
//            }
//            similarities[i] = similarity
//        }
//        
//        // Ordenar los índices por los valores de similitud en orden descendente
//        let bestPhotoIndices = similarities.enumerated().sorted(by: { $0.element > $1.element }).map { $0.offset }
//        
//        // Obtener los IDs de las mejores fotos
//        let bestPhotoIDs = bestPhotoIndices.prefix(10).map { photoIDs[$0] }
//        
//        print("Top 10 photo IDs (CPU): \(bestPhotoIDs)")
//    }

    
    
//    private func calculateAndPrintTopPhotoIDs(textFeatures: MLMultiArray) -> [String] {
//        guard let device = MTLCreateSystemDefaultDevice() else {
//            fatalError("Metal is not supported on this device")
//        }
//
//        let graph = MPSGraph()
//        // let textFeatures = MPSGraphExtensions.generateTextFeatures(device: device)
//        let textFeaturesArray = MPSGraphExtensions.convertTextFeaturesToMPSNDArray(textFeatures: textFeatures, device: device)
//        
//        // Obtener todos los vectores de fotos e IDs desde Core Data
//        let photoVectorsWithIDs = CoreDataManager.shared.fetchAllPhotoVectors()
//        let photoVectors = photoVectorsWithIDs.map { $0.vector }
//        let photoIDs = photoVectorsWithIDs.map { $0.id }
//        
//        // Crear un descriptor para el MPSNDArray
//        let photoFeaturesDescriptor = MPSNDArrayDescriptor(dataType: .float16, shape: [NSNumber(value: photoVectors.count), 512])
//        
//        // Crear el MPSNDArray utilizando el descriptor
//        let photoFeatures = MPSNDArray(device: device, descriptor: photoFeaturesDescriptor)
//        
//        
//
//        // let StartTime = DispatchTime.now()
//        
//        // mutable buffer
//        let totalSize = photoVectors.count * 512 * MemoryLayout<Float16>.stride
//        let buffer = UnsafeMutableBufferPointer<Float16>.allocate(capacity: totalSize / MemoryLayout<Float16>.stride)
//        defer { buffer.deallocate() }
//
//        var offset = 0
//        for vector in photoVectors {
//            let float16Pointer = vector.dataPointer.bindMemory(to: Float16.self, capacity: vector.count)
//            buffer.baseAddress!.advanced(by: offset).initialize(from: float16Pointer, count: vector.count)
//            offset += vector.count
//        }
//        photoFeatures.writeBytes(buffer.baseAddress!, strideBytes: nil)
//        
//        // Imprimir los primeros 10 elementos del buffer
////        print("Primeros 10 elementos del buffer (Float16):")
////        for i in 0..<min(1024, buffer.count) {
////            print("Elemento \(i): \(buffer[i])")
////        }
//        
////        var inputVals = [Float](repeating: 0, count: photoVectors.count * 512)
////        for (i, vector) in photoVectors.enumerated() {
////            let floatArray = vector.toFloatArray()
////            for j in 0..<512 {
////                inputVals[i * 512 + j] = floatArray[j]
////            }
////        }
////        // Copiar los datos al MPSNDArray
////        photoFeatures.writeBytes(&inputVals, strideBytes: nil)
//        
////        let EndTime = DispatchTime.now()
////        let NanoTime = EndTime.uptimeNanoseconds - StartTime.uptimeNanoseconds
////        let TimeInterval = Double(NanoTime) / 1_000_000
////        print("fill time: \(TimeInterval) \n")
//        
////        // Copiar los datos de photoVectors al MPSNDArray
////        for (index, vector) in photoVectors.enumerated() {
////            let floatArray = vector.toFloatArray()
////            var mutableFloatArray = floatArray // Crear una copia mutable
////            mutableFloatArray.withUnsafeMutableBytes { bufferPointer in
////                photoFeatures.writeBytes(bufferPointer.baseAddress!, strideBytes: nil)
////            }
////        }
//
//        
//        // Definir placeholders
//        let textTensor = graph.placeholder(shape: [1, 512] as [NSNumber], dataType: .float16, name: "text_features")
//        let photoTensor = graph.placeholder(shape: [NSNumber(value: photoVectors.count), 512] as [NSNumber], dataType: .float16, name: "photo_features")
//        
//        let similaritiesTensor = MPSGraphExtensions.calculateSimilarities(graph: graph, textTensor: textTensor, photoTensor: photoTensor)
//    
//        // Crear MPSGraphTensorData para feeds
//        let textFeaturesData = MPSGraphTensorData(textFeaturesArray)
//        let photoFeaturesData = MPSGraphTensorData(photoFeatures)
//
//
////        // Imprimir el contenido de textFeaturesData
////        let outputNDArray = textFeaturesData.mpsndarray()
////        var outputValues = [Float16](repeating: 0, count: 512)
////        outputNDArray.readBytes(&outputValues, strideBytes: nil)
////        print("textFeaturesData: \(outputValues)")
//
//
//        // Ejecutar el grafo
//        let results = graph.run(with: device.makeCommandQueue()!, feeds: [textTensor: textFeaturesData, photoTensor: photoFeaturesData], targetTensors: [similaritiesTensor], targetOperations: nil)
//        let similaritiesNDArray = results[similaritiesTensor]?.mpsndarray()
//        
//        var similarities = [Float16](repeating: 0, count: photoVectors.count)
//        similaritiesNDArray?.readBytes(&similarities, strideBytes: nil)
//        
////        print("Similarities vector: \(similarities)")
//        
//        let bestPhotoIndices = similarities.enumerated().sorted(by: { $0.element > $1.element }).map { $0.offset }
//        
//        // Obtener los IDs de las mejores fotos
//        let bestPhotoIDs = bestPhotoIndices.prefix(48).map { photoIDs[$0] }
//        
////        print("Top 48 photo IDs: \(bestPhotoIDs)")
//        
//        
//        return bestPhotoIDs
//    }
    
    private func calculateAndPrintTopPhotoIDs(textFeatures: MLMultiArray) -> [String] {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let graph = MPSGraph()
        let textFeaturesArray = MPSGraphExtensions.convertTextFeaturesToMPSNDArray(textFeatures: textFeatures, device: device)
        
        // Obtener todos los vectores de fotos e IDs desde Core Data
        let photoVectorsWithIDs = CoreDataManager.shared.fetchAllPhotoVectors()

        let photoVectors = photoVectorsWithIDs.map { $0.vector }
        let photoIDs = photoVectorsWithIDs.map { $0.id }
        
        // Crear un descriptor para el MPSNDArray
        let photoFeaturesDescriptor = MPSNDArrayDescriptor(dataType: .float16, shape: [NSNumber(value: photoVectors.count), 512])
        
        // Crear el MPSNDArray utilizando el descriptor
        let photoFeatures = MPSNDArray(device: device, descriptor: photoFeaturesDescriptor)
        
        // Llenar el MPSNDArray con los datos de los vectores
        let totalSize = photoVectors.count * 512 * MemoryLayout<Float16>.stride
        let buffer = UnsafeMutableBufferPointer<Float16>.allocate(capacity: totalSize / MemoryLayout<Float16>.stride)
        defer { buffer.deallocate() }

        var offset = 0
        for vector in photoVectors {
            let float16Pointer = vector.dataPointer.bindMemory(to: Float16.self, capacity: vector.count)
            buffer.baseAddress!.advanced(by: offset).initialize(from: float16Pointer, count: vector.count)
            offset += vector.count
        }
        photoFeatures.writeBytes(buffer.baseAddress!, strideBytes: nil)
        
        // Definir placeholders
        let textTensor = graph.placeholder(shape: [1, 512] as [NSNumber], dataType: .float16, name: "text_features")
        let photoTensor = graph.placeholder(shape: [NSNumber(value: photoVectors.count), 512] as [NSNumber], dataType: .float16, name: "photo_features")
        
        let similaritiesTensor = MPSGraphExtensions.calculateSimilarities(graph: graph, textTensor: textTensor, photoTensor: photoTensor)

        // Crear MPSGraphTensorData para feeds
        let textFeaturesData = MPSGraphTensorData(textFeaturesArray)
        let photoFeaturesData = MPSGraphTensorData(photoFeatures)

        // Ejecutar el grafo
        let results = graph.run(with: device.makeCommandQueue()!, feeds: [textTensor: textFeaturesData, photoTensor: photoFeaturesData], targetTensors: [similaritiesTensor], targetOperations: nil)
        let similaritiesNDArray = results[similaritiesTensor]?.mpsndarray()
        
        var similarities = [Float16](repeating: 0, count: photoVectors.count)
        similaritiesNDArray?.readBytes(&similarities, strideBytes: nil)
        
        let bestPhotoIndices = similarities.enumerated().sorted(by: { $0.element > $1.element }).map { $0.offset }
        
        // Obtener los IDs de las mejores fotos
        let bestPhotoIDs = bestPhotoIndices.prefix(48).map { photoIDs[$0] }
        
        return bestPhotoIDs
    }
    
    
}


















