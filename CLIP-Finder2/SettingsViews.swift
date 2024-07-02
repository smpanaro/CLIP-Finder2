//
//  SettingsViews.swift
//  CLIP-Finder2
//
//  Created by Fabio Guzman on 30/06/24.
//

import SwiftUI
import CoreML

//struct SettingsView: View {
//    @Environment(\.presentationMode) var presentationMode
//    @ObservedObject var photoGalleryViewModel: PhotoGalleryViewModel
//    @State private var showingAlert = false
//    
//   
//    var body: some View {
//        NavigationView {
//            Form {
//                Section {
//                    Button(action: {
//                        showingAlert = true
//                    }) {
//                        Text("Clear Photo Preprocessing Cache")
//                    }
//                    .foregroundColor(.red)
//                }
//            }
//            .navigationTitle("Settings")
//            .navigationBarItems(trailing: Button("Done") {
//                presentationMode.wrappedValue.dismiss()
//            })
//            .alert(isPresented: $showingAlert) {
//                Alert(
//                    title: Text("Clear Cache"),
//                    message: Text("Are you sure you want to clear the photo preprocessing cache? This action cannot be undone."),
//                    primaryButton: .destructive(Text("Clear")) {
//                        photoGalleryViewModel.reprocessPhotos()
//                        presentationMode.wrappedValue.dismiss()
//                    },
//                    secondaryButton: .cancel()
//                )
//            }
//        }
//    }
//    
//    
//    
//}
//
//

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var photoGalleryViewModel: PhotoGalleryViewModel
    @ObservedObject var modelProfiler = ModelProfiler.shared
    @State private var showingAlert = false
    @State private var isProfilerRunning = false
    
    @ViewBuilder
    private func createTableView(for modelType: ModelProfiler.ModelType) -> some View {
        VStack {
            HStack {
                Text("Compute Unit")
                    .font(.subheadline)
                    .frame(width: 100, alignment: .leading)
                Text("Median Time (ms)")
                    .font(.subheadline)
                    .frame(width: 100)
                Text("Average Time (ms)")
                    .font(.subheadline)
                    .frame(width: 100)
            }
            .padding(.vertical, 3)
            .background(Color.gray.opacity(0.2))
            
            ForEach(modelProfiler.processingUnitDescriptions.indices, id: \.self) { index in
                HStack {
                    Text(modelProfiler.processingUnitDescriptions[index])
                        .frame(width: 100, alignment: .leading)
                    Text(String(format: "%.2f", modelProfiler.getMedianForUnit(at: index, for: modelType)))
                        .frame(width: 100)
                    Text(String(format: "%.2f", modelProfiler.getAverageForUnit(at: index, for: modelType)))
                        .frame(width: 100)
                }
                .padding(.vertical, 3)
                .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.1))
            }
        }
        .padding(.vertical, 3)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button(action: {
                        showingAlert = true
                    }) {
                        Text("Clear Photo Preprocessing Cache")
                    }
                    .foregroundColor(.red)
                }
                
                Section {
                    Button(action: {
                        isProfilerRunning = true
                        Task {
                            await modelProfiler.runProfiler()
                            isProfilerRunning = false
                        }
                    }) {
                        Text(isProfilerRunning ? "Running Profiler..." : "Press to Run Model Profiler")
                    }
                    .disabled(isProfilerRunning)
                    
                    if !modelProfiler.profileResultsImage.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Clip Image Model")
                                .font(.headline)
                            
                            createTableView(for: .image)
                        }
                    }
                    
                    if !modelProfiler.profileResultsText.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Clip Text Model")
                                .font(.headline)
                            
                            createTableView(for: .text)
                        }
                    }
                } header: {
                    Text("Model Profiler")
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .alert(isPresented: $showingAlert) {
                Alert(
                    title: Text("Clear Cache"),
                    message: Text("Are you sure you want to clear the photo preprocessing cache? This action cannot be undone."),
                    primaryButton: .destructive(Text("Clear")) {
                        photoGalleryViewModel.reprocessPhotos()
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        
        
    }
}