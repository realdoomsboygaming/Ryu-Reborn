//
//  AnimeHeaderCell.swift
//  Ryu
//
//  Created by Francesco on 01/08/24.
//

import UIKit
import Alamofire

class AnimeHeaderCell: UITableViewCell {
    private let animeImageView = UIImageView()
    private let titleLabel = UILabel()
    private let aliasLabel = UILabel()
    private let bookmarkButton = UIButton(type: .system)
    private let optionsButton = UIImageView()
    private let starLabel = UILabel()
    private let airDateLabel = UILabel()
    private let starIconImageView = UIImageView()
    private let calendarIconImageView = UIImageView()
    
    var favoriteButtonTapped: (() -> Void)?
    var showOptionsMenu: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.backgroundColor = .secondarySystemBackground
        
        contentView.addSubview(animeImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(aliasLabel)
        contentView.addSubview(bookmarkButton)
        contentView.addSubview(optionsButton)
        contentView.addSubview(starLabel)
        contentView.addSubview(airDateLabel)
        contentView.addSubview(starIconImageView)
        contentView.addSubview(calendarIconImageView)
        
        [animeImageView, titleLabel, aliasLabel, bookmarkButton, optionsButton, starLabel, airDateLabel, starIconImageView, calendarIconImageView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        animeImageView.contentMode = .scaleAspectFill
        animeImageView.layer.cornerRadius = 8
        animeImageView.clipsToBounds = true
        
        titleLabel.font = UIFont.boldSystemFont(ofSize: 21)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 4
        
        aliasLabel.font = UIFont.systemFont(ofSize: 13)
        aliasLabel.textColor = .secondaryLabel
        aliasLabel.numberOfLines = 2
        
        bookmarkButton.setImage(UIImage(systemName: "bookmark"), for: .normal)
        bookmarkButton.tintColor = .systemTeal
        bookmarkButton.addTarget(self, action: #selector(favoriteButtonPressed), for: .touchUpInside)
        
        optionsButton.image = UIImage(systemName: "ellipsis.circle.fill")
        optionsButton.tintColor = .systemTeal
        optionsButton.isUserInteractionEnabled = true
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(optionsButtonTapped))
        optionsButton.addGestureRecognizer(tapGesture)
        
        starLabel.font = UIFont.boldSystemFont(ofSize: 15)
        starLabel.textColor = .secondaryLabel
        
        airDateLabel.font = UIFont.boldSystemFont(ofSize: 15)
        airDateLabel.textColor = .secondaryLabel
        
        starIconImageView.image = UIImage(systemName: "star.fill")
        starIconImageView.tintColor = .systemGray
        
        calendarIconImageView.image = UIImage(systemName: "calendar")
        calendarIconImageView.tintColor = .systemGray
        
        NSLayoutConstraint.activate([
            animeImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            animeImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            animeImageView.widthAnchor.constraint(equalToConstant: 110),
            animeImageView.heightAnchor.constraint(equalToConstant: 160),
            
            titleLabel.topAnchor.constraint(equalTo: animeImageView.topAnchor, constant: -4),
            titleLabel.leadingAnchor.constraint(equalTo: animeImageView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            
            aliasLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            aliasLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            aliasLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            
            bookmarkButton.bottomAnchor.constraint(equalTo: animeImageView.bottomAnchor),
            bookmarkButton.trailingAnchor.constraint(equalTo: optionsButton.leadingAnchor, constant: -15),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 30),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 30),
            
            optionsButton.bottomAnchor.constraint(equalTo: animeImageView.bottomAnchor),
            optionsButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            optionsButton.widthAnchor.constraint(equalToConstant: 30),
            optionsButton.heightAnchor.constraint(equalToConstant: 30),
            
            starIconImageView.topAnchor.constraint(equalTo: animeImageView.bottomAnchor, constant: 16),
            starIconImageView.leadingAnchor.constraint(equalTo: animeImageView.leadingAnchor),
            starIconImageView.widthAnchor.constraint(equalToConstant: 20),
            starIconImageView.heightAnchor.constraint(equalToConstant: 20),
            
            starLabel.bottomAnchor.constraint(equalTo: starIconImageView.bottomAnchor),
            starLabel.leadingAnchor.constraint(equalTo: starIconImageView.trailingAnchor),
            
            calendarIconImageView.topAnchor.constraint(equalTo: animeImageView.bottomAnchor, constant: 16),
            calendarIconImageView.trailingAnchor.constraint(equalTo: airDateLabel.leadingAnchor),
            calendarIconImageView.widthAnchor.constraint(equalToConstant: 20),
            calendarIconImageView.heightAnchor.constraint(equalToConstant: 20),
            
            airDateLabel.bottomAnchor.constraint(equalTo: calendarIconImageView.bottomAnchor),
            airDateLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            
            contentView.bottomAnchor.constraint(equalTo: calendarIconImageView.bottomAnchor, constant: 10)
        ])
    }
    
    @objc private func favoriteButtonPressed() {
        favoriteButtonTapped?()
    }
    
    @objc private func optionsButtonTapped() {
        showOptionsMenu?()
    }
    
    func configure(title: String?, imageUrl: String?, aliases: String, isFavorite: Bool, airdate: String, stars: String, href: String?) {
        titleLabel.text = title
        aliasLabel.text = aliases
        airDateLabel.text = airdate
        
        let selectedSource = UserDefaults.standard.string(forKey: "selectedMediaSource")
        
        switch selectedSource {
        case "AnimeWorld", "Anime3rb":
            starLabel.text = stars + "/10"
            airDateLabel.text = airdate
        case "GoGoAnime", "AnimeFire", "JKanime":
            starLabel.text = "N/A"
        default:
            starLabel.text = stars
            airDateLabel.text = airdate
        }
        
        if let url = URL(string: imageUrl ?? "") {
            animeImageView.kf.setImage(with: url, placeholder: UIImage(systemName: "photo"))
        }
        updateFavoriteButtonState(isFavorite: isFavorite)
        
        optionsButton.isUserInteractionEnabled = href != nil
    }
    
    private func updateFavoriteButtonState(isFavorite: Bool) {
        let imageName = isFavorite ? "bookmark.fill" : "bookmark"
        bookmarkButton.setImage(UIImage(systemName: imageName), for: .normal)
        bookmarkButton.tintColor = isFavorite ? .systemYellow : .systemTeal
    }
}
