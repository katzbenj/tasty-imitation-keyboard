
//
//  Database.swift
//  TastyImitationKeyboard
//
//  Created by Zack Burns on 10/16/16.
//  Copyright © 2016 Apple. All rights reserved.
//

import UIKit
import SQLite


class dbObjects {
    
    let db_path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    
    struct Ngrams {
        let table = Table("Ngrams")
        let gram = Expression<String>("gram")
        let n = Expression<Int>("n")
        let frequency = Expression<Float64>("frequency")
    }
    
    struct Profiles {
        let table = Table("Profiles")
        let profileId = Expression<Int64>("profileId")
        let name = Expression<String>("name")
        let linksTo = Expression<Int64>("linksTo")
    }
    
    struct Containers {
        let table = Table("Containers")
        let containerId = Expression<Int64>("containerId")
        let profile = Expression<String>("profile")
        let ngram = Expression<String>("ngram")
        let n = Expression<Int>("n")
        let frequency = Expression<Float64>("frequency")
        let lastused = Expression<Date>("lastused")
    }
    
    struct Phrases {
        let table = Table("Phrases")
        let phraseId = Expression<Int64>("id")
        let phrase = Expression<String>("phrase")
    }
    
    struct DataSources {
        let table = Table("DataSources")
        let profile = Expression<String>("profile")
        let title = Expression<String>("title")
        let source = Expression<String>("source")
    }
    
}

class Database: NSObject {
    
    var dbCreated = false
    var progressBar:UIProgressView? = nil
    var numElements = 30000
    var counter:Int = 0 {
        didSet {
            let progress = Float(counter) / Float(self.numElements)
            let animated = counter != 0
            if self.progressBar != nil {
                self.progressBar?.setProgress(progress, animated: animated)
            }
        }
    }
    
    override init() {
        super.init()
    }
    
    init(progressView:UIProgressView, numElements:Int) {
        super.init()
        self.numElements = numElements
        self.progressBar = progressView
        self.resetDatabase()
        do {
            
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            // Database object references
            let ngrams = dbObjects.Ngrams()
            let profiles = dbObjects.Profiles()
            let containers = dbObjects.Containers()
            let phrases = dbObjects.Phrases()
            let data_sources = dbObjects.DataSources()
            
            // Create Ngrams table
            _ = try? db.run(ngrams.table.create(ifNotExists: true) { t in
                t.column(ngrams.gram, primaryKey: true)
                t.column(ngrams.n)
                t.column(ngrams.frequency)
            })
            
            // Create Profiles table
            _ = try? db.run(profiles.table.create(ifNotExists: true) { t in
                t.column(profiles.profileId, primaryKey: .autoincrement)
                t.column(profiles.name)
                t.column(profiles.linksTo, defaultValue: 0)
            })
            
            // Insert the Default profile into the Profiles table if it doesn't exist
            
            if (try db.scalar(profiles.table.filter(profiles.name == "Default").count)) == 0 {
                let insert = profiles.table.insert(profiles.name <- "Default")
                _ = try? db.run(insert)
            }
            
            // Create Containers table (pairing of profile and ngram)
            _ = try? db.run(containers.table.create(ifNotExists: true) { t in
                t.column(containers.containerId, primaryKey: .autoincrement)
                t.column(containers.profile)
                t.column(containers.ngram)
                t.column(containers.n)
                t.column(containers.frequency, defaultValue: 0)
                t.column(containers.lastused, defaultValue: Date())
                // - - - - - - - - - - - - 
                t.unique(containers.profile, containers.ngram)
            })
            
            // Create Phrases table so user can store pre-defined phrases
            _ = try? db.run(phrases.table.create(ifNotExists: true) { t in
                t.column(phrases.phraseId, primaryKey: .autoincrement)
                t.column(phrases.phrase)
            })
            
            // Create DataSource table
            _ = try? db.run(data_sources.table.create(ifNotExists: true) { t in
                t.column(data_sources.profile)
                t.column(data_sources.title)
                t.column(data_sources.source)
            })
            
            
            let pathToWords = Bundle.main.path(forResource: "1grams", ofType: "txt")
            let pathToTwoGrams = Bundle.main.path(forResource: "2grams-10000", ofType: "txt")
            let pathToThreeGrams = Bundle.main.path(forResource: "3grams-10000", ofType: "txt")
            
            let wordsContent = try String(contentsOfFile:pathToWords!, encoding: String.Encoding.utf8)
            let allWords = wordsContent.components(separatedBy: "\n")
            
            let twoGramsContent = try String(contentsOfFile:pathToTwoGrams!,
                                             encoding: String.Encoding.utf8)
            // The format of the items in allTwoGrams is: <freq>\t<word1>\t<word2>
            let allTwoGrams = twoGramsContent.components(separatedBy: "\r\n")
            
            let threeGramsContent = try String(contentsOfFile:pathToThreeGrams!, encoding: String.Encoding.utf8)
            // The format of the items in allThreeGrams is: <freq>\t<word1>\t<word2>\t<word3>
            let allThreeGrams = threeGramsContent.components(separatedBy: "\r\n")
            
            self.counter = 0
            
            // Check to make sure Database has been created
            if self.dbCreated == true {
                return
            }
            
            // If not, then insert the missing words
            else {
                var ngrams_added = Set<String>()
                var bulk_ngrams_insert = "INSERT INTO Ngrams (gram, n, frequency) VALUES "
                var bulk_containers_insert = "INSERT INTO Containers (profile, ngram, n, frequency) VALUES "
                // Populate the Ngrams table and Container table with words
                for word in allWords {
                    if word == "" || word == " " {
                        break
                    }
                    let wordComponents = word.components(separatedBy: " ")
                    let frequency:Float64 = Float64(wordComponents[0])!
                    let oneGram = wordComponents[1]
                    
                    bulk_ngrams_insert.append("(\"\(oneGram)\",1,\(frequency)), ")
                    bulk_containers_insert.append("(\"Default\",\"\(oneGram)\",1,\(frequency)), ")

                    ngrams_added.insert(oneGram)

                    DispatchQueue.main.async {
                        self.counter += 1
                        return
                    }
                }
                self.counter = 9735
                
                for twoGram in allTwoGrams {
                    if twoGram == "" {
                        break
                    }
                    let twoGramComponents = twoGram.components(separatedBy: "\t")
                    var insertNgram = ""
                    var insert_n = Int()
                    let freq:Float64 = Float64(twoGramComponents[0])!
                    // if the word2 is "n't" then combine word1 and word2 and insert with n=1
                    if twoGramComponents[2] == "n't" {
                        insertNgram = twoGramComponents[1]+twoGramComponents[2]
                        insert_n = 1
                    }
                    // else insert with n=2
                    else {
                        insertNgram = twoGramComponents[1]+" "+twoGramComponents[2]
                        insert_n = 2
                    }
                    
                    if !ngrams_added.contains(insertNgram) {//result! == 0 {
                        bulk_ngrams_insert.append("(\"\(insertNgram)\",\(insert_n),\(freq)), ")
                        bulk_containers_insert.append("(\"Default\",\"\(insertNgram)\",\(insert_n),\(freq)), ")

                        ngrams_added.insert(insertNgram)
                    }
                    
                    DispatchQueue.main.async {
                        self.counter += 1
                        return
                    }
                }
                self.counter = 20000
                
                for threeGram in allThreeGrams {
                    if threeGram == "" {
                        break
                    }
                    let threeGramComponents = threeGram.components(separatedBy: "\t")
                    var word1 = threeGramComponents[1]
                    let word2 = threeGramComponents[2]
                    let word3 = threeGramComponents[3]
                    var insertNgram = ""
                    var insert_n = Int()
                    let freq:Float64 = Float64(threeGramComponents[0])!
                    // handle different cases of 3grams like we did with 2grams
                    if word1 == "n't" {
                        word1 = "not"
                    }
                    if word2 == "n't" {
                        insertNgram = word1+word2+" "+word3
                        insert_n = 2
                    }
                    else if word3 == "n't" {
                        insertNgram = word1+" "+word2+word3
                        insert_n = 2
                    }
                    else {
                        insertNgram = word1+" "+word2+" "+word3
                        insert_n = 3
                    }
   
                    if !ngrams_added.contains(insertNgram) {//result! == 0 {
                        bulk_ngrams_insert.append("(\"\(insertNgram)\",\(insert_n),\(freq)), ")
                        bulk_containers_insert.append("(\"Default\",\"\(insertNgram)\",\(insert_n),\(freq)), ")

                        ngrams_added.insert(insertNgram)
                    }
                    
                    DispatchQueue.main.async {
                        self.counter += 1
                        return
                    }
                }
                self.counter = 30000
                // --------------------------
                bulk_ngrams_insert = String(bulk_ngrams_insert.characters.dropLast(2))+";"
                _ = try db.run(bulk_ngrams_insert)
                
                bulk_containers_insert = String(bulk_containers_insert.characters.dropLast(2))+";"
                _ = try db.run(bulk_containers_insert)
                // --------------------------
                self.dbCreated = true
            }
        }
        catch {
            print("Error: \(error)")
        }
    }
    
    func insertIntoNgrams(input_ngram: String, n: Int) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let ngrams = dbObjects.Ngrams()
            let insert = ngrams.table.insert(ngrams.gram <- input_ngram, ngrams.n <- n)
            _ = try? db.run(insert)
        } catch {}
    }
    
    func insertAndIncrement(ngram: String, n: Int, new_freq: Float64 = -1.0) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            let containers = dbObjects.Containers()
            let currentProfile = UserDefaults.standard.value(forKey: "profile") as! String
            
            // if ngram notExists in database
            /*let exists_in_profile = try db.scalar(containers.table
                .filter(containers.ngram == ngram)
                .filter(containers.profile == currentProfile)
                .count) > 0
            let exists_in_default = try db.scalar(containers.table
                .filter(containers.ngram == ngram)
                .filter(containers.profile == "Default")
                .count) > 0*/
            if true { //(!exists_in_profile) {
                // insert ngram into profile
                let insert = containers.table.insert(containers.ngram <- ngram,
                                                     containers.profile <- currentProfile,
                                                     containers.n <- n)
                _ = try? db.run(insert)
            }
            if true {//(!exists_in_default) {
                // insert ngram into Default
                let insert = containers.table.insert(containers.ngram <- ngram,
                                                     containers.profile <- "Default",
                                                     containers.n <- n)
                _ = try? db.run(insert)
            }
            
            if new_freq == -1 {
                // increment ngram in current_profile and default cases
                _ = try db.run(containers.table.filter(containers.ngram == ngram)
                    .filter(containers.profile == currentProfile)
                    .update(containers.frequency += 1.0, containers.lastused <- Date()))
                _ = try db.run(containers.table.filter(containers.ngram == ngram)
                    .filter(containers.profile == "Default")
                    .update(containers.frequency += 1.0, containers.lastused <- Date()))
            }
            else {
                // set the frequency to the one provided
                _ = try db.run(containers.table.filter(containers.ngram == ngram)
                    .filter(containers.profile == currentProfile)
                    .update(containers.frequency += new_freq, containers.lastused <- Date()))
                _ = try db.run(containers.table.filter(containers.ngram == ngram)
                    .filter(containers.profile == "Default")
                    .update(containers.frequency += new_freq, containers.lastused <- Date()))
            }
            
        }
        catch {
            print("Something failed in insertAndIncrement()")
            print("Error: \(error)")
        }
    }
    
    func recommendationQuery(user_profile: String, n: Int, pattern: String,
                             words: [String], result_set: Set<String>) -> Set<String> {
        
        if result_set.count == 14 {
            return result_set
        }
        
        // Copy result_set into resultSet so we can manipulate resultSet
        var resultSet = result_set
        
        let word1 = words[0]
        let word2 = words[1]
        let current_input = words[2]
        
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            let containers = dbObjects.Containers()
            
            for row in try db.prepare(containers.table
                .filter(containers.profile == user_profile)
                .filter(containers.ngram.like(pattern))
                .filter(containers.ngram != current_input)
                .filter(containers.ngram != "")
                .filter(containers.n == n)
                .order(containers.frequency.desc, containers.ngram)
                .limit(14, offset: 0)) {
                    // This wall have a different number of components for different patterns!
                    let row_components = row[containers.ngram].components(separatedBy: " ")
                    
                    // POSSIBLE PATTERNS
                    // 3:      "\(word1) \(word2) \(current_input)%"
                    // 3:      "% \(word2) \(current_input)%"
                    // 3 & 2:  "\(word2) \(current_input)%"
                    // 2 & 1:  "\(current_input)%"
                    
                    if n == 3 {
                        if pattern == "\(word1) \(word2) \(current_input)%" {
                            if resultSet.count < 14 {
                                resultSet.insert(row_components[2])
                            }
                        }
                        else if pattern == "\(word2) \(current_input)%" {
                            if resultSet.count < 14 {
                                resultSet.insert(row_components[1]+" "+row_components[2])
                            }
                        }
                    }
                    else if n == 2 {
                        if pattern == "\(word2) \(current_input)%" {
                            if resultSet.count < 14 {
                                resultSet.insert(row_components[1])
                            }
                        }
                        else if pattern == "\(current_input)%" {
                            if resultSet.count < 14 {
                                resultSet.insert(row_components[0]+" "+row_components[1])
                            }
                        }
                    }
                    else /* n == 1 */ {
                        if resultSet.count < 14 {
                            resultSet.insert(row[containers.ngram])
                        }
                    }
                    
            }
        } catch {
            print("Something went wrong when fetching \(n)grams for input '\(current_input)' in \(user_profile)")
            print("Error: \(error)")
        }
        return resultSet
    }
    
    /*
     enum ShiftState {
         case disabled
         case enabled
         case locked
     }
    */
 
    func recommendWords(word1: String = "", word2: String = "", current_input: String,
                        shift_state: ShiftState = ShiftState.disabled)->Set<String>{
        // POSSIBLE PATTERNS
        // 3:      "\(word1) \(word2) \(current_input)%"
        // 3:      "% \(word2) \(current_input)%" ********* <--- maybe not
        // 3 & 2:  "\(word2) \(current_input)%"
        // 2 & 1:  "\(current_input)%"
        
        var resultSet = Set<String>()
        let userProfile = UserDefaults.standard.value(forKey: "profile")
        let words = [word1, word2, current_input]
        
        if word1 != "" && word2 != "" {
            resultSet = recommendationQuery(user_profile: userProfile as! String,
                                n: 3, pattern: "\(word1) \(word2) \(current_input)%",
                                words: words, result_set: resultSet)
            for n in [2,3] {
                resultSet = recommendationQuery(user_profile: userProfile as! String,
                                n: n, pattern: "\(word2) \(current_input)%",
                                words: words, result_set: resultSet)
            }
            for n in [1,2] {
                resultSet = recommendationQuery(user_profile: userProfile as! String,
                                n: n, pattern: "\(current_input)%",
                                words: words, result_set: resultSet)
            }
        }
            
        else if word1 == "" && word2 != "" {
            for n in [2,3] {
                resultSet = recommendationQuery(user_profile: userProfile as! String,
                                n: n, pattern: "\(word2) \(current_input)%",
                                words: words, result_set: resultSet)
            }
            for n in [1,2] {
                resultSet = recommendationQuery(user_profile: userProfile as! String,
                                n: n, pattern: "\(current_input)%",
                                words: words, result_set: resultSet)
            }
        }
            
        else /* word1 and word2 are empty */ {
            resultSet = recommendationQuery(user_profile: userProfile as! String,
                                n: 1, pattern: "\(current_input)%",
                                words: words, result_set: resultSet)
        }
        // Fix resultSet based on the ShiftState
        //  disabled: do nothing
        //  enabled: capitalize the first letter
        //  locked: make everything CAPS
        for word in resultSet {
            if shift_state == ShiftState.disabled {
                break
            }
            else if shift_state == ShiftState.enabled {
                let placeholder = word.capitalized
                resultSet.remove(word)
                resultSet.insert(placeholder)
            }
            else {
                let placeholder = word.uppercased()
                resultSet.remove(word)
                resultSet.insert(placeholder)
            }
        }
        
        return resultSet
    }
    
    func addProfile(profile_name:String){
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            // Insert the new profile into the database
            let profiles = dbObjects.Profiles()
            
            let insert = profiles.table.insert(profiles.name <- profile_name)
            _ = try? db.run(insert) // will throw error if profile already exists
            
            // Insert all of the original words into the new profile
            let ngrams = dbObjects.Ngrams()
            
            self.counter = 0
            var bulk_insert = "INSERT INTO Containers (profile, ngram, n, frequency) VALUES "
            
            for row in try db.prepare(ngrams.table) {
                bulk_insert.append("(\"\(profile_name)\",\"\(row[ngrams.gram])\",\(row[ngrams.n]),\(row[ngrams.frequency])), ")
                
                DispatchQueue.main.async {
                    self.counter += 1
                    return
                }
            }
            self.counter = 30000
            
            _ = try? db.run(String(bulk_insert.characters.dropLast(2))+";")
            
        } catch {
            print("Something failed while trying to add new profile")
            print("Error: \(error)")
        }
    }
    

    // WARNING: NOT TESTED YET
    func deleteProfile(profile_name: String) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            // Delete profile from Profiles
            let profiles = dbObjects.Profiles()
            _ = try db.run(profiles.table.filter(profiles.name == profile_name).delete())
            
            // Delete all ngrams associated with profile from Containers
            let containers = dbObjects.Containers()
            _ = try db.run(containers.table.filter(containers.profile == profile_name).delete())
            
            // Delete all data sources associated with profile
            let data_sources = dbObjects.DataSources()
            _ = try db.run(data_sources.table.filter(data_sources.profile == profile_name).delete())
            
        } catch {
            print("Something failed while trying to delete profile")
            print("Error: \(error)")
        }
    }
    
    // WARNING: NOT TESTED YET
    func editProfileName(current_name: String, new_name: String) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let profiles = dbObjects.Profiles()
            let containers = dbObjects.Containers()
            let data_sources = dbObjects.DataSources()
            
            _ = try db.run(profiles.table
                            .filter(profiles.name == current_name)
                            .update(profiles.name <- new_name))
            _ = try db.run(containers.table
                            .filter(containers.profile == current_name)
                            .update(containers.profile <- new_name))
            _ = try db.run(data_sources.table
                            .filter(data_sources.profile == current_name)
                            .update(data_sources.profile <- new_name))
        } catch {
            print("Something failed while editing profile name")
            print("Error: \(error)")
        }
    }
    
    // WARNING: NOT TESTED YET
    func getProfiles() -> [String] {
        var profiles_list: [String] = []
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let profiles = dbObjects.Profiles()
            
            for row in try db.prepare(profiles.table) {
                profiles_list.append(row[profiles.name])
            }
        } catch {
            print("Something failed while getting list of profiles")
            print("Error: \(error)")
        }
        return profiles_list
    }
    
    // WARNING: NOT TESTED YET
    func addDataSource(target_profile: String, new_data_source: String, new_title: String) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let data_sources = dbObjects.DataSources()
            
            let insert = data_sources.table.insert(data_sources.profile <- target_profile,
                                                   data_sources.source <- new_data_source,
                                                   data_sources.title <- new_title)
            _ = try? db.run(insert)
        } catch {
            print("Something failed while trying to insert new data source")
            print("Error: \(error)")
        }
    }
    
    // WARNING: NOT TESTED YET
    // WARNING: only deletes the reference to the data source in the target profile, 
    //          DOES NOT delete all of the ngrams that were generated from that source
    func removeDataSource(target_profile: String, data_source: String) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let data_sources = dbObjects.DataSources()
            
            _ = try db.run(data_sources.table.filter(data_sources.profile == target_profile)
                                         .filter(data_sources.source == data_source).delete())
        } catch {
            print("Something failed while removing data source")
            print("Error: \(error)")
        }
    }
    
    // WARNING: NOT TESTED YET
    func getDataSources(target_profile: String) -> [String] {
        var data_sources_list: [String] = []
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let data_sources = dbObjects.DataSources()
            
            for row in try db.prepare(data_sources.table
                .filter(data_sources.profile == target_profile)) {
                    data_sources_list.append(row[data_sources.source])
            }
        } catch {
            print("Something failed while getting list of data sources")
            print("Error: \(error)")
        }
        return data_sources_list
    }
    
    func resetDatabase() {
        let ngrams = dbObjects.Ngrams()
        let profiles = dbObjects.Profiles()
        let containers = dbObjects.Containers()
        let phrases = dbObjects.Phrases()
        let data_sources = dbObjects.DataSources()
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            _ = try? db.run(ngrams.table.drop(ifExists: true))
            _ = try? db.run(profiles.table.drop(ifExists: true))
            _ = try? db.run(containers.table.drop(ifExists: true))
            _ = try? db.run(phrases.table.drop(ifExists: true))
            _ = try? db.run(data_sources.table.drop(ifExists: true))
            self.dbCreated = false
        } catch {
            print("reset failed")
            print("Error: \(error)")
        }
    }
    
    func addPhrase(phrase: String) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let phrases = dbObjects.Phrases()
            
            let insert = phrases.table.insert(phrases.phrase <- phrase)
            _ = try? db.run(insert)
        }
        catch {
            print("Inserting a new phrase failed")
            print("Error: \(error)")
        }
    }
    
    func editPhrase(old_phrase: String, new_phrase: String) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let phrases = dbObjects.Phrases()
            
            _ = try db.run(phrases.table.filter(phrases.phrase == old_phrase)
                                        .update(phrases.phrase <- new_phrase))
        }
        catch {
            print("Editing a phrase failed")
            print("Error: \(error)")
        }
    }
    
    func deletePhrase(phrase: String) {
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let phrases = dbObjects.Phrases()
            
            _ = try db.run(phrases.table.filter(phrases.phrase == phrase).delete())
        }
        catch {
            print("Deleting a phrase failed")
            print("Error: \(error)")
        }
    }
    
    func getPhrases() -> [String] {
        var phrase_list: [String] = []
        do {
            let db_path = dbObjects().db_path
            let db = try Connection("\(db_path)/db.sqlite3")
            
            let phrases = dbObjects.Phrases()
            
            for row in try db.prepare(phrases.table) {
                phrase_list.append(row[phrases.phrase])
            }
        } catch {
            print("Something failed while getting list of profiles")
            print("Error: \(error)")
        }
        return phrase_list
    }
    
    
}
